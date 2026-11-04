package android.system;

/** JVM stand-in for android.system.StructStat (API 21): only st_mode. */
public final class StructStat {
    public final int st_mode;
    public StructStat(int mode) { this.st_mode = mode; }
}
