package android.content;

import android.net.Uri;

/** JVM stand-in, needed only to compile the pre-fix source in the negative control. */
public final class ContentUris {
    public static Uri withAppendedId(Uri base, long id) { return Uri.parse(base + "/" + id); }
}
