package treasurelevelmobs.patch;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.ByteArrayOutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipOutputStream;

import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.Opcodes;
import org.objectweb.asm.tree.AbstractInsnNode;
import org.objectweb.asm.tree.ClassNode;
import org.objectweb.asm.tree.InsnList;
import org.objectweb.asm.tree.JumpInsnNode;
import org.objectweb.asm.tree.LabelNode;
import org.objectweb.asm.tree.LdcInsnNode;
import org.objectweb.asm.tree.MethodInsnNode;
import org.objectweb.asm.tree.MethodNode;
import org.objectweb.asm.tree.VarInsnNode;

/** Deterministically patches the exact Treasure Level Mobs build used by Regnum. */
public final class PatchTreasureLevelMobs {
    private static final String SPAWN_CLASS =
        "net/mcreator/treasurelevelmobs/procedures/MobspawnProcedure.class";
    private static final String TICK_CLASS =
        "net/mcreator/treasurelevelmobs/procedures/MobtickProcedure.class";
    private static final String HELPER_CLASS =
        "treasurelevelmobs/patch/RegnumLevelCap.class";
    private static final String EXECUTE_DESCRIPTOR =
        "(Lnet/neoforged/bus/api/Event;Lnet/minecraft/world/level/LevelAccessor;DDDLnet/minecraft/world/entity/Entity;)V";
    private static final String COMPOUND_TAG = "net/minecraft/nbt/CompoundTag";
    private static final String HELPER = "treasurelevelmobs/patch/RegnumLevelCap";

    private PatchTreasureLevelMobs() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 3) {
            throw new IllegalArgumentException("usage: PatchTreasureLevelMobs INPUT_JAR OUTPUT_JAR HELPER_CLASS");
        }
        Path input = Paths.get(args[0]).toAbsolutePath();
        Path output = Paths.get(args[1]).toAbsolutePath();
        Path helper = Paths.get(args[2]).toAbsolutePath();
        if (input.equals(output)) {
            throw new IllegalArgumentException("refusing to overwrite the input jar");
        }
        if (!Files.isRegularFile(input) || !Files.isRegularFile(helper)) {
            throw new IOException("input jar or helper class is missing");
        }
        byte[] helperBytes = Files.readAllBytes(helper);
        Path temporary = output.resolveSibling(output.getFileName() + ".tmp");
        Files.deleteIfExists(temporary);
        try {
            patchJar(input, temporary, helperBytes);
            Files.move(temporary, output, StandardCopyOption.REPLACE_EXISTING,
                StandardCopyOption.ATOMIC_MOVE);
        } finally {
            Files.deleteIfExists(temporary);
        }
    }

    private static void patchJar(Path input, Path output, byte[] helperBytes) throws IOException {
        int spawnPatched = 0;
        int tickPatched = 0;
        try (ZipFile source = new ZipFile(input.toFile());
             OutputStream file = Files.newOutputStream(output);
             ZipOutputStream destination = new ZipOutputStream(file)) {
            java.util.Enumeration<? extends ZipEntry> entries = source.entries();
            while (entries.hasMoreElements()) {
                ZipEntry entry = entries.nextElement();
                if (entry.getName().equals(HELPER_CLASS)) {
                    continue;
                }
                byte[] bytes;
                try (InputStream stream = source.getInputStream(entry)) {
                    bytes = readAll(stream);
                }
                if (entry.getName().equals(SPAWN_CLASS)) {
                    bytes = patchSpawn(bytes);
                    spawnPatched++;
                } else if (entry.getName().equals(TICK_CLASS)) {
                    bytes = patchTick(bytes);
                    tickPatched++;
                }
                ZipEntry copy = new ZipEntry(entry.getName());
                copy.setTime(entry.getTime());
                destination.putNextEntry(copy);
                destination.write(bytes);
                destination.closeEntry();
            }
            ZipEntry helperEntry = new ZipEntry(HELPER_CLASS);
            // Keep generated jars byte-for-byte reproducible across runs.
            helperEntry.setTime(0L);
            destination.putNextEntry(helperEntry);
            destination.write(helperBytes);
            destination.closeEntry();
        }
        if (spawnPatched != 1 || tickPatched != 1) {
            throw new IOException("expected one spawn and one tick class, got "
                + spawnPatched + " and " + tickPatched);
        }
    }

    private static byte[] patchSpawn(byte[] original) throws IOException {
        ClassNode node = readClass(original);
        MethodNode method = findExecute(node);

        int divisorReplacements = 0;
        for (AbstractInsnNode instruction : method.instructions) {
            if (instruction instanceof LdcInsnNode) {
                LdcInsnNode ldc = (LdcInsnNode) instruction;
                if (ldc.cst instanceof Double
                    && ((Double) ldc.cst).doubleValue() == 10_000.0) {
                    ldc.cst = 100_000.0;
                    divisorReplacements++;
                }
            }
        }
        if (divisorReplacements != 1) {
            throw new IOException("expected one 10000.0 distance divisor, got " + divisorReplacements);
        }

        List<MethodInsnNode> levelWrites = findLevelWrites(method);
        if (levelWrites.size() != 4) {
            throw new IOException("expected four tlmobslevel writes, got " + levelWrites.size());
        }
        method.instructions.insert(levelWrites.get(0), capCall());
        method.instructions.insert(levelWrites.get(levelWrites.size() - 1), capCall());
        return writeClass(node);
    }

    private static byte[] patchTick(byte[] original) throws IOException {
        ClassNode node = readClass(original);
        MethodNode method = findExecute(node);
        LabelNode afterNullCheck = null;
        for (AbstractInsnNode instruction : method.instructions) {
            if (instruction instanceof JumpInsnNode) {
                JumpInsnNode jump = (JumpInsnNode) instruction;
                if (jump.getOpcode() == Opcodes.IFNONNULL) {
                    afterNullCheck = jump.label;
                    break;
                }
            }
        }
        if (afterNullCheck == null) {
            throw new IOException("could not find MobtickProcedure null guard");
        }

        LabelNode skip = new LabelNode();
        InsnList migration = new InsnList();
        migration.add(new VarInsnNode(Opcodes.ALOAD, 8));
        migration.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL,
            "net/minecraft/world/entity/Entity", "getPersistentData",
            "()Lnet/minecraft/nbt/CompoundTag;", false));
        migration.add(new VarInsnNode(Opcodes.ASTORE, 25));
        migration.add(new VarInsnNode(Opcodes.ALOAD, 25));
        migration.add(new LdcInsnNode("tlmobslevel"));
        migration.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, COMPOUND_TAG,
            "contains", "(Ljava/lang/String;)Z", false));
        migration.add(new JumpInsnNode(Opcodes.IFEQ, skip));
        migration.add(new VarInsnNode(Opcodes.ALOAD, 1));
        migration.add(new VarInsnNode(Opcodes.ALOAD, 8));
        migration.add(new MethodInsnNode(Opcodes.INVOKESTATIC, HELPER, "migrate",
            "(Ljava/lang/Object;Ljava/lang/Object;)V", false));
        migration.add(skip);
        method.instructions.insert(afterNullCheck, migration);
        return writeClass(node);
    }

    private static InsnList capCall() {
        InsnList call = new InsnList();
        call.add(new VarInsnNode(Opcodes.ALOAD, 1));
        call.add(new VarInsnNode(Opcodes.ALOAD, 8));
        call.add(new MethodInsnNode(Opcodes.INVOKESTATIC, HELPER, "capPersistentLevel",
            "(Ljava/lang/Object;Ljava/lang/Object;)V", false));
        return call;
    }

    private static List<MethodInsnNode> findLevelWrites(MethodNode method) {
        List<MethodInsnNode> writes = new ArrayList<>();
        for (AbstractInsnNode instruction : method.instructions) {
            if (!(instruction instanceof MethodInsnNode)) {
                continue;
            }
            MethodInsnNode call = (MethodInsnNode) instruction;
            if (!call.owner.equals(COMPOUND_TAG)
                || !call.name.equals("putDouble")
                || !call.desc.equals("(Ljava/lang/String;D)V")) {
                continue;
            }
            AbstractInsnNode next = call;
            for (int distance = 0; distance < 40 && next != null; distance++) {
                next = previousMeaningful(next);
                if (next == null) {
                    break;
                }
                if (next instanceof LdcInsnNode) {
                    LdcInsnNode ldc = (LdcInsnNode) next;
                    if ("tlmobslevel".equals(ldc.cst)) {
                        AbstractInsnNode value = nextMeaningful(ldc);
                        // Skill flags read tlmobslevel before writing their own key.
                        boolean isRead = value instanceof MethodInsnNode
                            && ((MethodInsnNode) value).owner.equals(COMPOUND_TAG)
                            && ((MethodInsnNode) value).name.equals("getDouble");
                        if (!isRead) {
                            writes.add(call);
                        }
                        break;
                    }
                }
            }
        }
        return writes;
    }

    private static AbstractInsnNode previousMeaningful(AbstractInsnNode instruction) {
        AbstractInsnNode previous = instruction.getPrevious();
        while (previous != null && previous.getOpcode() == -1) {
            previous = previous.getPrevious();
        }
        return previous;
    }

    private static AbstractInsnNode nextMeaningful(AbstractInsnNode instruction) {
        AbstractInsnNode next = instruction.getNext();
        while (next != null && next.getOpcode() == -1) {
            next = next.getNext();
        }
        return next;
    }

    private static MethodNode findExecute(ClassNode node) throws IOException {
        for (MethodNode method : node.methods) {
            if (method.name.equals("execute") && method.desc.equals(EXECUTE_DESCRIPTOR)
                && (method.access & Opcodes.ACC_PRIVATE) != 0) {
                return method;
            }
        }
        throw new IOException("private execute method not found in " + node.name);
    }

    private static ClassNode readClass(byte[] bytes) {
        ClassNode node = new ClassNode();
        new ClassReader(bytes).accept(node, 0);
        return node;
    }

    private static byte[] readAll(InputStream stream) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int read;
        while ((read = stream.read(buffer)) != -1) {
            output.write(buffer, 0, read);
        }
        return output.toByteArray();
    }

    private static byte[] writeClass(ClassNode node) {
        ClassWriter writer = new ClassWriter(ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS) {
            @Override
            protected String getCommonSuperClass(String type1, String type2) {
                return "java/lang/Object";
            }
        };
        node.accept(writer);
        return writer.toByteArray();
    }
}
