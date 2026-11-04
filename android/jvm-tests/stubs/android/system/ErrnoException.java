package android.system;

/** JVM stand-in for android.system.ErrnoException (API 21). */
public final class ErrnoException extends Exception {
    public final int errno;
    public ErrnoException(String functionName, int errno) {
        super(functionName);
        this.errno = errno;
    }
}
