import Foundation

public final class GameSessionTracker: @unchecked Sendable {
    public static let shared = GameSessionTracker()
    
    private var activeSessions: [String: GameSession] = [:]
    private let lock = NSLock()
    
    private init() {}
    
    public func startSession(store: GameStore, gameId: String, gameName: String?, engine: String, graphics: String) {
        lock.lock()
        defer { lock.unlock() }
        
        let key = sessionKey(store: store, gameId: gameId)
        activeSessions[key] = GameSession(
            store: store,
            gameId: gameId,
            gameName: gameName,
            engine: engine,
            graphics: graphics,
            startTime: Date()
        )
    }
    
    public func endSession(store: GameStore, gameId: String) -> GameSession? {
        lock.lock()
        defer { lock.unlock() }
        
        let key = sessionKey(store: store, gameId: gameId)
        return activeSessions.removeValue(forKey: key)
    }
    
    public func getSession(store: GameStore, gameId: String) -> GameSession? {
        lock.lock()
        defer { lock.unlock() }
        
        let key = sessionKey(store: store, gameId: gameId)
        return activeSessions[key]
    }
    
    public func clearAllSessions() {
        lock.lock()
        defer { lock.unlock()
        
        activeSessions.removeAll()
    }
    
    private func sessionKey(store: GameStore, gameId: String) -> String {
        "\(store.identifier):\(gameId)"
    }
}
