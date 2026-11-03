package android.provider;

import android.content.Context;
import android.net.Uri;

/** JVM stand-in: any /document/<id> path counts as a document URI, whatever the authority. */
public final class DocumentsContract {
    private static final String PREFIX = "/document/";
    public static boolean isDocumentUri(Context context, Uri uri) {
        return uri.getPath() != null && uri.getPath().startsWith(PREFIX);
    }
    public static String getDocumentId(Uri uri) { return uri.getPath().substring(PREFIX.length()); }
}
