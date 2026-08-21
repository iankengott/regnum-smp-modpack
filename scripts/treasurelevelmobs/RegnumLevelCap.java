package treasurelevelmobs.patch;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.Locale;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

/** Runtime helper bundled into the patched Treasure Level Mobs jar. */
public final class RegnumLevelCap {
    public static final double MAX_LEVEL = 100.0;
    public static final double BLOCKS_PER_LEVEL = 100.0;
    public static final double DISTANCE_DIVISOR = 100_000.0;
    // The imported map's center. Distance is horizontal, so Y is retained
    // only to document the complete center coordinate supplied by the map.
    public static final double WORLD_CENTER_X = 13_013.5;
    public static final double WORLD_CENTER_Y = 84.0;
    public static final double WORLD_CENTER_Z = 8_136.5;

    private static final String LEVEL_KEY = "tlmobslevel";
    private static final String ATTRIBUTE_LEVEL_KEY = "regnum_tlmobs_attribute_level";
    private static final String[] HIGH_LEVEL_FLAGS = {
        "tlmobsspeed",
        "tlmobscritical",
        "tlmobsshield",
        "tptlmobs",
        "tlmobsbreak",
        "tlmobsbadeffect",
        "tlmobssummon",
        "tlmobsdamage",
        "tlmobsarmorbreak",
        "tlmobsgoodeffect"
    };

    private static final ConcurrentMap<String, Method> METHOD_CACHE = new ConcurrentHashMap<>();
    private static volatile Object WORLD_CENTER_BLOCK;
    private static volatile boolean warned;

    private RegnumLevelCap() {
    }

    /** Converts Manhattan blocks from the map center into the allowed level. */
    public static double capForDistance(double blocks) {
        if (!Double.isFinite(blocks) || blocks < 0.0) {
            blocks = 0.0;
        }
        return Math.min(MAX_LEVEL, Math.max(1.0, Math.floor(blocks / BLOCKS_PER_LEVEL)));
    }

    /** Returns the Manhattan distance from the configured map center. */
    public static double distanceFromWorldCenter(double x, double z) {
        if (!Double.isFinite(x) || !Double.isFinite(z)) {
            return 0.0;
        }
        return Math.abs(x - WORLD_CENTER_X) + Math.abs(z - WORLD_CENTER_Z);
    }

    /**
     * Supplies a BlockPos approximation of the map center to the patched
     * generated procedure. The authoritative level cap uses the exact double
     * center above; this position only feeds the mod's legacy distance term.
     * The ignored argument consumes the original LevelData receiver so the
     * bytecode replacement remains stack-compatible without Minecraft on the
     * patcher compile classpath.
     */
    public static Object worldCenter(Object ignored) throws Exception {
        Object center = WORLD_CENTER_BLOCK;
        if (center != null) {
            return center;
        }
        Class<?> blockPos = Class.forName("net.minecraft.core.BlockPos");
        Object resolved = blockPos.getConstructor(int.class, int.class, int.class)
            .newInstance((int) Math.floor(WORLD_CENTER_X),
                (int) Math.floor(WORLD_CENTER_Y),
                (int) Math.floor(WORLD_CENTER_Z));
        WORLD_CENTER_BLOCK = resolved;
        return resolved;
    }

    /** Caps a newly generated level without changing the mod's progression inputs. */
    public static void capPersistentLevel(Object level, Object entity) {
        try {
            if (entity == null) {
                return;
            }
            if (isClientSide(level)) {
                return;
            }
            Object data = call(entity, "getPersistentData");
            double current = number(call(data, "getDouble", LEVEL_KEY));
            double cap = distanceCap(level, entity);
            if (!Double.isFinite(current) || current > cap) {
                call(data, "putDouble", LEVEL_KEY, Math.max(1.0, cap));
            }
        } catch (Throwable error) {
            warnOnce("could not cap a newly generated mob", error);
        }
    }

    /**
     * Migrates one existing mob. The helper is called from the mod's entity tick
     * procedure, so old entities are corrected when their chunks load.
     */
    public static void migrate(Object level, Object entity) {
        try {
            if (entity == null) {
                return;
            }
            if (isClientSide(level)) {
                return;
            }
            Object data = call(entity, "getPersistentData");
            double current = number(call(data, "getDouble", LEVEL_KEY));
            double cap = distanceCap(level, entity);
            if (Double.isFinite(current) && !(current > cap)) {
                return;
            }

            double previousAttributeLevel = Double.isFinite(current) ? current : cap;
            if (Boolean.TRUE.equals(call(data, "contains", ATTRIBUTE_LEVEL_KEY))) {
                previousAttributeLevel = number(call(data, "getDouble", ATTRIBUTE_LEVEL_KEY));
            }

            double next = Math.max(1.0, cap);
            call(data, "putDouble", LEVEL_KEY, next);
            adjustAttributes(entity, previousAttributeLevel, next);
            call(data, "putDouble", ATTRIBUTE_LEVEL_KEY, next);

            // These abilities are only granted by the original mod above level 100.
            if (current > MAX_LEVEL) {
                for (String key : HIGH_LEVEL_FLAGS) {
                    call(data, "putDouble", key, 0.0);
                }
            }
            updateName(entity, next);
        } catch (Throwable error) {
            warnOnce("could not migrate an existing mob", error);
        }
    }

    private static double distanceCap(Object level, Object entity) throws Exception {
        double x = number(call(entity, "getX"));
        double z = number(call(entity, "getZ"));
        return capForDistance(distanceFromWorldCenter(x, z));
    }

    private static boolean isClientSide(Object level) throws Exception {
        return Boolean.TRUE.equals(call(level, "isClientSide"));
    }

    private static void adjustAttributes(Object entity, double previous, double next) throws Exception {
        Class<?> livingEntity = Class.forName("net.minecraft.world.entity.LivingEntity");
        if (!livingEntity.isInstance(entity)) {
            return;
        }
        Class<?> attributes = Class.forName("net.minecraft.world.entity.ai.attributes.Attributes");
        adjustAttribute(entity, livingEntity, attributes, "ATTACK_DAMAGE", previous, next, 0);
        adjustAttribute(entity, livingEntity, attributes, "MAX_HEALTH", previous, next, 1);
        adjustAttribute(entity, livingEntity, attributes, "MOVEMENT_SPEED", previous, next, 2);
        Object maxHealth = call(entity, "getMaxHealth");
        call(entity, "setHealth", ((Number) maxHealth).floatValue());
    }

    private static void adjustAttribute(Object entity, Class<?> livingEntity, Class<?> attributes,
                                        String fieldName, double previous, double next,
                                        int adjustmentType) throws Exception {
        Field field = attributes.getField(fieldName);
        Object holder = field.get(null);
        Method getAttribute = findMethod(livingEntity, "getAttribute", 1);
        Object instance = getAttribute.invoke(entity, holder);
        if (instance == null) {
            return;
        }
        double base = number(call(instance, "getBaseValue"));
        double updated = base - adjustment(previous, adjustmentType) + adjustment(next, adjustmentType);
        call(instance, "setBaseValue", updated);
    }

    private static double adjustment(double level, int type) {
        if (type == 0) {
            return Math.ceil(level / 10.0);
        }
        if (type == 1) {
            return Math.ceil(level / 2.0);
        }
        return level / 1000.0;
    }

    private static void updateName(Object entity, double level) throws Exception {
        Object displayName = call(entity, "getDisplayName");
        String current = String.valueOf(call(displayName, "getString"));
        String base = current.replaceFirst("^Lv[-+0-9.eE]+\\s+", "");
        Class<?> component = Class.forName("net.minecraft.network.chat.Component");
        Object nextName = findMethod(component, "literal", 1).invoke(null,
            String.format(Locale.ROOT, "Lv%s %s", level, base));
        findMethod(entity.getClass(), "setCustomName", 1).invoke(entity, nextName);
    }

    private static Object call(Object target, String name, Object... arguments) throws Exception {
        if (target == null) {
            throw new NullPointerException(name + " target");
        }
        Class<?> type = target.getClass();
        String key = type.getName() + "#" + name + "/" + arguments.length;
        Method method = METHOD_CACHE.get(key);
        if (method == null) {
            method = findMethod(type, name, arguments.length);
            Method previous = METHOD_CACHE.putIfAbsent(key, method);
            if (previous != null) {
                method = previous;
            }
        }
        return method.invoke(target, arguments);
    }

    private static Method findMethod(Class<?> type, String name, int parameterCount) throws NoSuchMethodException {
        for (Method method : type.getMethods()) {
            if (method.getName().equals(name) && method.getParameterCount() == parameterCount) {
                return method;
            }
        }
        throw new NoSuchMethodException(type.getName() + "." + name + "/" + parameterCount);
    }

    private static double number(Object value) {
        return ((Number) value).doubleValue();
    }

    private static void warnOnce(String message, Throwable error) {
        if (!warned) {
            warned = true;
            System.err.println("[RegnumLevelCap] " + message + ": " + error);
        }
    }

}
