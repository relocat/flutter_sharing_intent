package android.webkit;

/** JVM stand-in: maps the few MIME types the tests use. */
public final class MimeTypeMap {
    private static final MimeTypeMap INSTANCE = new MimeTypeMap();
    public static MimeTypeMap getSingleton() { return INSTANCE; }
    public String getExtensionFromMimeType(String mime) {
        if ("image/jpeg".equals(mime)) return "jpg";
        return null;
    }
}
