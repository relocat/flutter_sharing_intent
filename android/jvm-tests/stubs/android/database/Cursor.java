package android.database;

/** JVM stand-in: only the methods the plugin calls. */
public interface Cursor {
    boolean moveToFirst();
    int getColumnIndexOrThrow(String column);
    String getString(int index);
    void close();
}
