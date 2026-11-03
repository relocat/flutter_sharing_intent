package android.content;

import java.io.File;

/** JVM stand-in for the two Context members the plugin's copy code uses. */
public class Context {
    private final File cacheDir;
    private final ContentResolver resolver = new ContentResolver();

    public Context(File cacheDir) { this.cacheDir = cacheDir; }
    public File getCacheDir() { return cacheDir; }
    public ContentResolver getContentResolver() { return resolver; }
}
