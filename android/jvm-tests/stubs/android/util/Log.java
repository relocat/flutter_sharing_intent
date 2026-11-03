package android.util;

import java.util.ArrayList;
import java.util.List;

/** JVM stand-in that records every message so tests can inspect what was logged. */
public final class Log {
    public static final List<String> MESSAGES = new ArrayList<>();
    public static int i(String tag, String msg) { MESSAGES.add(msg); return 0; }
    public static int w(String tag, String msg) { MESSAGES.add(msg); return 0; }
    public static int d(String tag, String msg) { MESSAGES.add(msg); return 0; }
    public static int e(String tag, String msg) { MESSAGES.add(msg); return 0; }
}
