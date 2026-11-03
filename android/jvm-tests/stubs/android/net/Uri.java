package android.net;

import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;

/** Minimal JVM stand-in for android.net.Uri (test stub, not the platform class). */
public final class Uri {
    private final String raw;
    private final String scheme;
    private final String authority;
    private final String path;

    private Uri(String raw) {
        this.raw = raw;
        int schemeEnd = raw.indexOf("://");
        scheme = schemeEnd < 0 ? null : raw.substring(0, schemeEnd);
        String rest = schemeEnd < 0 ? raw : raw.substring(schemeEnd + 3);
        int slash = rest.indexOf('/');
        String auth = slash < 0 ? rest : rest.substring(0, slash);
        authority = auth.isEmpty() ? null : auth;
        String rawPath = slash < 0 ? "" : rest.substring(slash);
        path = URLDecoder.decode(rawPath.replace("+", "%2B"), StandardCharsets.UTF_8);
    }

    public static Uri parse(String value) { return new Uri(value); }
    public String getScheme() { return scheme; }
    public String getAuthority() { return authority; }
    public String getPath() { return path; }
    @Override public String toString() { return raw; }
}
