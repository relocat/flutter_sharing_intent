package android.content;

import android.database.Cursor;
import android.net.Uri;
import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;

/** JVM stand-in: serves display names, bytes and MIME types registered by the test. */
public class ContentResolver {
    public final Map<String, String> displayNames = new HashMap<>();
    public final Map<String, byte[]> contents = new HashMap<>();
    public final Map<String, String> types = new HashMap<>();

    public Cursor query(Uri uri, String[] projection, String selection, String[] args, String order) {
        final String name = displayNames.get(uri.toString());
        if (name == null) return null;
        return new Cursor() {
            public boolean moveToFirst() { return true; }
            public int getColumnIndexOrThrow(String column) { return 0; }
            public String getString(int index) { return name; }
            public void close() { }
        };
    }

    public InputStream openInputStream(Uri uri) {
        byte[] bytes = contents.get(uri.toString());
        return bytes == null ? null : new ByteArrayInputStream(bytes);
    }

    public String getType(Uri uri) { return types.get(uri.toString()); }
}
