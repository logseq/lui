package dev.lui;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;

/** Drives the production JNI exports against a real OCaml application. */
public final class LuiBridge {
    private static native int nativeVirtualRowsVersion();
    private static native int nativeStart(int platform, int host);
    private static native int nativePress(long node);
    private static native int nativeVirtualWindow(long node, long generation, long first, long last, long[] pins);
    private static native int nativeResync();
    private static native int nativeStop();

    private static void dispatchPatch(byte[] bytes) {
        System.out.println("PATCH " + new String(bytes, StandardCharsets.UTF_8));
    }

    public static void main(String[] args) throws Exception {
        System.load(args[0]);
        int version = nativeVirtualRowsVersion();
        System.out.println("VERSION " + version);
        System.out.println("RESULT " + nativeStart(3, version == 1 ? 260 : 4));
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        String line;
        while ((line = reader.readLine()) != null) {
            String[] values = line.split(" ");
            int result;
            switch (values[0]) {
                case "press": result = nativePress(Long.parseLong(values[1])); break;
                case "window": {
                    long[] pins = new long[values.length - 5];
                    for (int i = 5; i < values.length; i++) pins[i - 5] = Long.parseLong(values[i]);
                    result = nativeVirtualWindow(Long.parseLong(values[1]), Long.parseLong(values[2]),
                            Long.parseLong(values[3]), Long.parseLong(values[4]), pins);
                    break;
                }
                case "null": result = nativeVirtualWindow(1, 1, 0, 1, null); break;
                case "resync": result = nativeResync(); break;
                case "stop": System.out.println("RESULT " + nativeStop()); return;
                default: throw new IllegalArgumentException(line);
            }
            System.out.println("RESULT " + result);
        }
    }
}
