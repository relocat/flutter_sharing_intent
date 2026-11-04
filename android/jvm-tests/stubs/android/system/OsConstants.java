package android.system;

/** JVM stand-in for the android.system.OsConstants members the plugin uses (API 21). */
public final class OsConstants {
    public static final int ENOENT = 2;
    public static final int ENOTDIR = 20;
    public static final int S_IFMT = 0170000;
    public static final int S_IFLNK = 0120000;
    public static final int S_IFDIR = 0040000;
    public static final int S_IFREG = 0100000;
    public static boolean S_ISLNK(int mode) { return (mode & S_IFMT) == S_IFLNK; }
    public static boolean S_ISDIR(int mode) { return (mode & S_IFMT) == S_IFDIR; }
    public static boolean S_ISREG(int mode) { return (mode & S_IFMT) == S_IFREG; }
}
