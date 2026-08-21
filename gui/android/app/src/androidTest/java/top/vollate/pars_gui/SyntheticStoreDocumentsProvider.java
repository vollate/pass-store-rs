package top.vollate.pars_gui;

import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;
import android.provider.DocumentsContract;
import android.provider.DocumentsProvider;
import java.io.ByteArrayOutputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.zip.DeflaterOutputStream;

/** Deterministic read-only DocumentsProvider installed only in the instrumentation APK. */
public final class SyntheticStoreDocumentsProvider extends DocumentsProvider {
  public static final String AUTHORITY = "top.vollate.pars_gui.synthetic.documents";
  public static final String FULL_ROOT = "full";
  public static final String LOCAL_ROOT = "local";
  public static final String INVALID_GIT_ROOT = "invalid-git";
  public static final String UNSAFE_ROOT = "unsafe";
  public static final String CYCLE_ROOT = "cycle";
  public static final int OBJECT_COUNT = 256;
  public static final String STATS_DOCUMENT = "__stats";

  private static final Map<String, AtomicInteger> QUERY_ATTEMPTS = new ConcurrentHashMap<>();
  private static final AtomicInteger OPEN_CALLS = new AtomicInteger();
  private static final AtomicInteger MUTATION_CALLS = new AtomicInteger();
  private static final String[] ROOT_PROJECTION = {
    DocumentsContract.Root.COLUMN_ROOT_ID,
    DocumentsContract.Root.COLUMN_DOCUMENT_ID,
    DocumentsContract.Root.COLUMN_TITLE,
    DocumentsContract.Root.COLUMN_FLAGS
  };
  private static final String[] DOCUMENT_PROJECTION = {
    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
    DocumentsContract.Document.COLUMN_MIME_TYPE,
    DocumentsContract.Document.COLUMN_FLAGS,
    DocumentsContract.Document.COLUMN_SIZE
  };

  @Override public boolean onCreate() { return true; }

  @Override public Cursor queryRoots(String[] projection) {
    String[] columns = projection != null ? projection : ROOT_PROJECTION;
    MatrixCursor cursor = new MatrixCursor(columns);
    for (String rootId : Arrays.asList(
        FULL_ROOT, LOCAL_ROOT, INVALID_GIT_ROOT, UNSAFE_ROOT, CYCLE_ROOT)) {
      Node root = nodes(rootId).get(rootId);
      Object[] row = new Object[columns.length];
      for (int i = 0; i < columns.length; i++) row[i] = rootColumn(columns[i], root);
      cursor.addRow(row);
    }
    return cursor;
  }

  @Override public Cursor queryDocument(String documentId, String[] projection)
      throws FileNotFoundException {
    String[] columns = projection != null ? projection : DOCUMENT_PROJECTION;
    Node node = node(documentId);
    if (node.parentId == null && !documentId.endsWith("/" + STATS_DOCUMENT)) reset(documentId);
    MatrixCursor cursor = new MatrixCursor(columns);
    addDocumentRow(cursor, columns, node);
    return cursor;
  }

  @Override public Cursor queryChildDocuments(
      String parentDocumentId, String[] projection, String sortOrder) throws FileNotFoundException {
    String[] columns = projection != null ? projection : DOCUMENT_PROJECTION;
    String rootId = rootId(parentDocumentId);
    int attempt = QUERY_ATTEMPTS.computeIfAbsent(parentDocumentId, ignored -> new AtomicInteger())
        .incrementAndGet();
    MatrixCursor cursor = new MatrixCursor(columns);
    if (FULL_ROOT.equals(parentDocumentId) && attempt <= 2) {
      if (attempt == 2) {
        Bundle extras = new Bundle();
        extras.putBoolean(DocumentsContract.EXTRA_LOADING, true);
        cursor.setExtras(extras);
      }
      return cursor;
    }
    if ((CYCLE_ROOT + "/loop").equals(parentDocumentId)) {
      addDocumentRow(cursor, columns, new Node(CYCLE_ROOT, parentDocumentId, "again",
          DocumentsContract.Document.MIME_TYPE_DIR, new byte[0]));
      return cursor;
    }
    List<Node> children = new ArrayList<>();
    for (Node candidate : nodes(rootId).values()) {
      if (parentDocumentId.equals(candidate.parentId)) children.add(candidate);
    }
    Collections.sort(children, Comparator.comparing(value -> value.name));
    for (Node child : children) addDocumentRow(cursor, columns, child);
    return cursor;
  }

  @Override public DocumentsContract.Path findDocumentPath(
      String parentDocumentId, String childDocumentId) throws FileNotFoundException {
    String root = rootId(childDocumentId);
    List<String> path = new ArrayList<>();
    path.add(root);
    if (!root.equals(childDocumentId)) path.add(childDocumentId);
    return new DocumentsContract.Path(root, path);
  }

  @Override public boolean isChildDocument(String parentDocumentId, String documentId) {
    return documentId.equals(parentDocumentId) || documentId.startsWith(parentDocumentId + "/");
  }

  @Override public ParcelFileDescriptor openDocument(
      String documentId, String mode, CancellationSignal signal) throws FileNotFoundException {
    if (!"r".equals(mode)) throw new FileNotFoundException("Synthetic provider is read-only");
    Node node = node(documentId);
    if (node.directory()) throw new FileNotFoundException("Cannot open directory");
    boolean stats = documentId.endsWith("/" + STATS_DOCUMENT);
    if (!stats) OPEN_CALLS.incrementAndGet();
    byte[] bytes = stats ? statsText(rootId(documentId)).getBytes(StandardCharsets.UTF_8) : node.bytes;
    try {
      ParcelFileDescriptor[] pipe = ParcelFileDescriptor.createPipe();
      new Thread(() -> {
        try (OutputStream output = new ParcelFileDescriptor.AutoCloseOutputStream(pipe[1])) {
          output.write(bytes);
        } catch (IOException ignored) {
          // The reader owns cancellation; test assertions observe incomplete copy as failure.
        }
      }, "synthetic-document-writer").start();
      return pipe[0];
    } catch (IOException error) {
      throw new FileNotFoundException(error.getMessage());
    }
  }

  @Override public Bundle call(String method, String arg, Bundle extras) {
    if ("reset".equals(method)) {
      reset(arg != null ? arg : FULL_ROOT);
      Bundle result = new Bundle();
      result.putString("digest", digest(arg != null ? arg : FULL_ROOT));
      return result;
    }
    if ("stats".equals(method)) {
      String root = arg != null ? arg : FULL_ROOT;
      Bundle result = new Bundle();
      result.putInt("rootAttempts", attempts(root));
      result.putInt("openCalls", OPEN_CALLS.get());
      result.putInt("mutationCalls", MUTATION_CALLS.get());
      result.putString("digest", digest(root));
      return result;
    }
    return super.call(method, arg, extras);
  }

  private static void reset(String ignoredRoot) {
    QUERY_ATTEMPTS.clear();
    OPEN_CALLS.set(0);
    MUTATION_CALLS.set(0);
  }

  private static int attempts(String root) {
    AtomicInteger value = QUERY_ATTEMPTS.get(root);
    return value == null ? 0 : value.get();
  }

  private static String statsText(String root) {
    return attempts(root) + "|" + OPEN_CALLS.get() + "|" + MUTATION_CALLS.get() + "|" + digest(root);
  }

  private static Node node(String documentId) throws FileNotFoundException {
    String root = rootId(documentId);
    if ((root + "/" + STATS_DOCUMENT).equals(documentId)) {
      return new Node(documentId, null, STATS_DOCUMENT, "text/plain", new byte[0]);
    }
    Node value = nodes(root).get(documentId);
    if (value == null) throw new FileNotFoundException(documentId);
    return value;
  }

  private static String rootId(String documentId) throws FileNotFoundException {
    for (String root : Arrays.asList(
        FULL_ROOT, LOCAL_ROOT, INVALID_GIT_ROOT, UNSAFE_ROOT, CYCLE_ROOT)) {
      if (documentId.equals(root) || documentId.startsWith(root + "/")) return root;
    }
    throw new FileNotFoundException(documentId);
  }

  private static Map<String, Node> nodes(String root) {
    LinkedHashMap<String, Node> values = new LinkedHashMap<>();
    String title;
    if (FULL_ROOT.equals(root)) title = "Synthetic Vault";
    else if (LOCAL_ROOT.equals(root)) title = "Local Vault";
    else if (INVALID_GIT_ROOT.equals(root)) title = "Invalid Git Vault";
    else if (UNSAFE_ROOT.equals(root)) title = "Unsafe Vault";
    else title = "Cycle Vault";
    directory(values, root, null, title);
    file(values, root + "/.gpg-id", root, ".gpg-id", "SYNTHETIC-RECIPIENT\n");
    file(values, root + "/login.gpg", root, "login.gpg", "synthetic ciphertext");
    directory(values, root + "/folder", root, "folder");
    file(values, root + "/folder/nested.gpg", root + "/folder", "nested.gpg",
        "nested synthetic ciphertext");
    if (FULL_ROOT.equals(root)) {
      directory(values, root + "/.git", root, ".git");
      file(values, root + "/.git/HEAD", root + "/.git", "HEAD", "ref: refs/heads/main\n");
      file(values, root + "/.git/config", root + "/.git", "config",
          "[core]\nrepositoryformatversion = 0\n[remote \"origin\"]\n"
              + "url = https://example.invalid/synthetic.git\n");
      directory(values, root + "/.git/refs", root + "/.git", "refs");
      directory(values, root + "/.git/refs/heads", root + "/.git/refs", "heads");
      directory(values, root + "/.git/objects", root + "/.git", "objects");
      GitObject blob = gitObject("blob", "synthetic ciphertext".getBytes(StandardCharsets.UTF_8));
      byte[] treePrefix = "100644 login.gpg\0".getBytes(StandardCharsets.UTF_8);
      byte[] treeBytes = new byte[treePrefix.length + 20];
      System.arraycopy(treePrefix, 0, treeBytes, 0, treePrefix.length);
      System.arraycopy(hexBytes(blob.id), 0, treeBytes, treePrefix.length, 20);
      GitObject tree = gitObject("tree", treeBytes);
      String commitText = "tree " + tree.id + "\n"
          + "author Synthetic <synthetic@example.invalid> 0 +0000\n"
          + "committer Synthetic <synthetic@example.invalid> 0 +0000\n\n"
          + "synthetic import fixture\n";
      GitObject commit = gitObject("commit", commitText.getBytes(StandardCharsets.UTF_8));
      addGitObject(values, root, blob);
      addGitObject(values, root, tree);
      addGitObject(values, root, commit);
      file(values, root + "/.git/refs/heads/main", root + "/.git/refs/heads", "main",
          commit.id + "\n");
      for (int index = 0; index < OBJECT_COUNT; index++) {
        addGitObject(
            values,
            root,
            gitObject(
                "blob",
                ("synthetic-object-" + index).getBytes(StandardCharsets.UTF_8)));
      }
    } else if (INVALID_GIT_ROOT.equals(root)) {
      directory(values, root + "/.git", root, ".git");
      file(values, root + "/.git/HEAD", root + "/.git", "HEAD", "not-a-valid-head\n");
      file(values, root + "/.git/config", root + "/.git", "config",
          "[core]\nrepositoryformatversion = 0\n");
    } else if (UNSAFE_ROOT.equals(root)) {
      file(values, root + "/unsafe", root, "../escape", "must not be opened");
    } else if (CYCLE_ROOT.equals(root)) {
      directory(values, root + "/loop", root, "loop");
    }
    return values;
  }

  private static void directory(Map<String, Node> values, String id, String parent, String name) {
    values.put(id, new Node(id, parent, name, DocumentsContract.Document.MIME_TYPE_DIR, new byte[0]));
  }

  private static void file(
      Map<String, Node> values, String id, String parent, String name, String content) {
    fileBytes(values, id, parent, name, content.getBytes(StandardCharsets.UTF_8));
  }

  private static void fileBytes(
      Map<String, Node> values, String id, String parent, String name, byte[] content) {
    values.put(id, new Node(id, parent, name, "application/octet-stream", content));
  }

  private static GitObject gitObject(String type, byte[] content) {
    byte[] header = (type + " " + content.length + "\0").getBytes(StandardCharsets.UTF_8);
    byte[] canonical = new byte[header.length + content.length];
    System.arraycopy(header, 0, canonical, 0, header.length);
    System.arraycopy(content, 0, canonical, header.length, content.length);
    try {
      MessageDigest digest = MessageDigest.getInstance("SHA-1");
      StringBuilder id = new StringBuilder();
      for (byte value : digest.digest(canonical)) id.append(String.format("%02x", value));
      ByteArrayOutputStream compressed = new ByteArrayOutputStream();
      try (DeflaterOutputStream output = new DeflaterOutputStream(compressed)) {
        output.write(canonical);
      }
      return new GitObject(id.toString(), compressed.toByteArray());
    } catch (NoSuchAlgorithmException | IOException impossible) {
      throw new AssertionError(impossible);
    }
  }

  private static byte[] hexBytes(String value) {
    byte[] result = new byte[value.length() / 2];
    for (int index = 0; index < result.length; index++) {
      result[index] = (byte) Integer.parseInt(value.substring(index * 2, index * 2 + 2), 16);
    }
    return result;
  }

  private static void addGitObject(Map<String, Node> values, String root, GitObject object) {
    String directoryId = root + "/.git/objects/" + object.id.substring(0, 2);
    if (!values.containsKey(directoryId)) {
      directory(values, directoryId, root + "/.git/objects", object.id.substring(0, 2));
    }
    String name = object.id.substring(2);
    fileBytes(values, directoryId + "/" + name, directoryId, name, object.compressed);
  }

  private static final class GitObject {
    final String id;
    final byte[] compressed;

    GitObject(String id, byte[] compressed) {
      this.id = id;
      this.compressed = compressed;
    }
  }

  private static String digest(String root) {
    try {
      MessageDigest digest = MessageDigest.getInstance("SHA-256");
      List<Node> ordered = new ArrayList<>(nodes(root).values());
      Collections.sort(ordered, Comparator.comparing(value -> value.id));
      for (Node value : ordered) {
        digest.update(value.id.getBytes(StandardCharsets.UTF_8));
        digest.update((byte) 0);
        digest.update(value.name.getBytes(StandardCharsets.UTF_8));
        digest.update((byte) 0);
        digest.update(value.mimeType.getBytes(StandardCharsets.UTF_8));
        digest.update((byte) 0);
        digest.update(value.bytes);
      }
      StringBuilder result = new StringBuilder();
      for (byte value : digest.digest()) result.append(String.format("%02x", value));
      return result.toString();
    } catch (NoSuchAlgorithmException impossible) {
      throw new AssertionError(impossible);
    }
  }

  private static void addDocumentRow(MatrixCursor cursor, String[] columns, Node node) {
    Object[] row = new Object[columns.length];
    for (int i = 0; i < columns.length; i++) row[i] = documentColumn(columns[i], node);
    cursor.addRow(row);
  }

  private static Object documentColumn(String column, Node node) {
    if (DocumentsContract.Document.COLUMN_DOCUMENT_ID.equals(column)) return node.id;
    if (DocumentsContract.Document.COLUMN_DISPLAY_NAME.equals(column)) return node.name;
    if (DocumentsContract.Document.COLUMN_MIME_TYPE.equals(column)) return node.mimeType;
    if (DocumentsContract.Document.COLUMN_FLAGS.equals(column)) return 0;
    if (DocumentsContract.Document.COLUMN_SIZE.equals(column)) return (long) node.bytes.length;
    if (DocumentsContract.Document.COLUMN_LAST_MODIFIED.equals(column)) return 1L;
    return null;
  }

  private static Object rootColumn(String column, Node node) {
    if (DocumentsContract.Root.COLUMN_ROOT_ID.equals(column)) return node.id;
    if (DocumentsContract.Root.COLUMN_DOCUMENT_ID.equals(column)) return node.id;
    if (DocumentsContract.Root.COLUMN_TITLE.equals(column)) return node.name;
    if (DocumentsContract.Root.COLUMN_FLAGS.equals(column)) return DocumentsContract.Root.FLAG_SUPPORTS_IS_CHILD;
    if (DocumentsContract.Root.COLUMN_MIME_TYPES.equals(column)) return "*/*";
    return null;
  }

  public static Uri treeUri(String root) {
    return DocumentsContract.buildTreeDocumentUri(AUTHORITY, root);
  }

  private static final class Node {
    final String id;
    final String parentId;
    final String name;
    final String mimeType;
    final byte[] bytes;

    Node(String id, String parentId, String name, String mimeType, byte[] bytes) {
      this.id = id;
      this.parentId = parentId;
      this.name = name;
      this.mimeType = mimeType;
      this.bytes = bytes;
    }

    boolean directory() {
      return DocumentsContract.Document.MIME_TYPE_DIR.equals(mimeType);
    }
  }
}
