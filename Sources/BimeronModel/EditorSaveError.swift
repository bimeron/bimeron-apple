public enum EditorSaveError: Error, Sendable {
    case staleOriginal
    case changedStaging
}
