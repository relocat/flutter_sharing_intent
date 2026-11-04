package android.system;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.NoSuchFileException;
import java.nio.file.Paths;

/**
 * JVM stand-in for android.system.Os (API 21). The JDK's lstat equivalent
 * (java.nio.file, API 26 on Android) is used ONLY here, inside the test stub;
 * the plugin itself must not touch java.nio.file.
 */
public final class Os {
    public static StructStat lstat(String path) throws ErrnoException {
        try {
            Object mode = Files.getAttribute(Paths.get(path), "unix:mode", LinkOption.NOFOLLOW_LINKS);
            return new StructStat((Integer) mode);
        } catch (NoSuchFileException e) {
            throw new ErrnoException("lstat", OsConstants.ENOENT);
        } catch (IOException e) {
            String message = String.valueOf(e.getMessage());
            throw new ErrnoException("lstat", message.contains("Not a directory") ? OsConstants.ENOTDIR : 5);
        }
    }
}
