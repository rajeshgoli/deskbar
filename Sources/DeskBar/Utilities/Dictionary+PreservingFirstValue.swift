extension Dictionary {
    init<S: Sequence>(preservingFirstValues pairs: S) where S.Element == (Key, Value) {
        self.init()

        for (key, value) in pairs where self[key] == nil {
            self[key] = value
        }
    }
}
