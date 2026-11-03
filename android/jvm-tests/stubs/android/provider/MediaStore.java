package android.provider;

import android.net.Uri;

/** JVM stand-in, needed only to compile the pre-fix source in the negative control. */
public final class MediaStore {
    public static final class Images { public static final class Media { public static final Uri EXTERNAL_CONTENT_URI = Uri.parse("content://media/external/images/media"); } }
    public static final class Video { public static final class Media { public static final Uri EXTERNAL_CONTENT_URI = Uri.parse("content://media/external/video/media"); } }
    public static final class Audio { public static final class Media { public static final Uri EXTERNAL_CONTENT_URI = Uri.parse("content://media/external/audio/media"); } }
}
