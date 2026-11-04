package android.content;

import android.database.Cursor;
import android.net.Uri;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;

/** JVM stand-in: serves display names, bytes and MIME types registered by the test. */
public class ContentResolver {
    public final Map<String, String> displayNames = new HashMap<>();
    public final Map<String, byte[]> contents = new HashMap<>();
    public final Map<String, String> types = new HashMap<>();

    public Cursor query(Uri uri, String[] projection, String selection, String[] args, String order) {
        if (queryThrows != null) ContentResolver.<RuntimeException>sneakyThrow(queryThrows);
        final String name = displayNames.get(uri.toString());
        if (name == null) return null;
        return new Cursor() {
            public boolean moveToFirst() { return true; }
            public int getColumnIndexOrThrow(String column) { return 0; }
            public String getString(int index) { return name; }
            public void close() { }
        };
    }

    /** When set, openInputStream throws it (checked exceptions included). */
    public Throwable openThrows;
    /** URIs whose stream fails with an IOException on open. */
    public final java.util.Set<String> failingUris = new java.util.HashSet<>();
    /** When set, query throws it. */
    public Throwable queryThrows;
    /** When >= 0, reading fails with an IOException after this many bytes. */
    public int failReadAfterBytes = -1;

    @SuppressWarnings("unchecked")
    private static <T extends Throwable> void sneakyThrow(Throwable t) throws T { throw (T) t; }

    public InputStream openInputStream(Uri uri) {
        if (openThrows != null) ContentResolver.<RuntimeException>sneakyThrow(openThrows);
        if (failingUris.contains(uri.toString())) ContentResolver.<RuntimeException>sneakyThrow(new IOException("simulated open failure"));
        byte[] bytes = contents.get(uri.toString());
        if (bytes == null) return null;
        if (failReadAfterBytes < 0) return new ByteArrayInputStream(bytes);
        final int limit = failReadAfterBytes;
        return new ByteArrayInputStream(bytes) {
            @Override public synchronized int read(byte[] b, int off, int len) {
                if (pos >= limit) ContentResolver.<RuntimeException>sneakyThrow(new IOException("simulated read failure"));
                return super.read(b, off, Math.min(len, limit - pos));
            }
        };
    }

    public String getType(Uri uri) { return types.get(uri.toString()); }
}
