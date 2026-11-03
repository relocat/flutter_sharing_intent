package android.os;

import java.io.File;

/** JVM stand-in, needed only to compile the pre-fix source in the negative control. */
public final class Environment {
    public static File getExternalStorageDirectory() { return new File("/storage/emulated/0"); }
}
