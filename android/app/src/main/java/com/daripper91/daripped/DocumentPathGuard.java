package com.daripper91.daripped.filepicker;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;

/**
 * Pure path-confinement helpers for {@link TinyDocumentsProvider}. Kept free of Android
 * classes so they can be exercised with plain Java and temporary directories.
 * <p/>
 * Document ids stay absolute paths (so already persisted grants keep working) but are never
 * trusted as strings: they are canonicalised and compared against the canonical root.
 */
final class DocumentPathGuard {

    private static final int MAX_NAME_LENGTH = 200;

    private DocumentPathGuard() {
    }

    /** True when canonical {@code f} is {@code base} or below it ("containers_evil" is not below "containers"). */
    static boolean isInside(File base, File f) {
        final String b = base.getPath();
        final String p = f.getPath();
        final String prefix = b.endsWith(File.separator) ? b : b + File.separator;
        return p.equals(b) || p.startsWith(prefix);
    }

    /**
     * Resolve a document id to a canonical file inside {@code base}. Resolves "..", "." and
     * symlinks, so a link inside a guest rootfs cannot point outside the root.
     */
    static File resolve(File base, String docId) throws FileNotFoundException {
        if (docId == null) throw new FileNotFoundException("Missing document id");
        final File f;
        try {
            f = new File(docId).getCanonicalFile();
        } catch (IOException e) {
            throw new FileNotFoundException("Cannot resolve " + docId);
        }
        if (!isInside(base, f)) {
            throw new FileNotFoundException(docId + " is outside the containers root");
        }
        if (!f.exists()) throw new FileNotFoundException(f.getAbsolutePath() + " not found");
        return f;
    }

    /** True when both ids are inside {@code base} and the child is inside the parent. Fails closed. */
    static boolean isChild(File base, String parentDocumentId, String documentId) {
        if (parentDocumentId == null || documentId == null) return false;
        try {
            final File parent = new File(parentDocumentId).getCanonicalFile();
            final File child = new File(documentId).getCanonicalFile();
            return isInside(base, parent) && isInside(parent, child);
        } catch (IOException e) {
            return false;
        }
    }

    /** One path segment only: no separators, NULs, "." or "..", capped at 200 chars. */
    static String sanitizeDisplayName(String name) {
        if (name == null) name = "";
        name = name.replace('/', '_').replace('\\', '_').replace('\0', '_').trim();
        if (name.isEmpty() || name.equals(".") || name.equals("..")) name = "untitled";
        if (name.length() > MAX_NAME_LENGTH) name = name.substring(0, MAX_NAME_LENGTH);
        return name;
    }
}
