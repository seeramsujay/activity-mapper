import Foundation
import SQLite3

class DatabaseHelper {
    static let shared = DatabaseHelper()
    private var db: OpaquePointer?

    private init() {
        openDatabase()
    }

    private func openDatabase() {
        let fileManager = FileManager.default
        guard let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("TurnBack DB: Failed to locate documents directory")
            return
        }
        let dbPath = documentsUrl.appendingPathComponent("turnback.db").path
        
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("TurnBack DB: Failed to open SQLite database at \(dbPath)")
            return
        }

        // Enable Write-Ahead Logging for concurrent read/write support
        execute(sql: "PRAGMA journal_mode=WAL;")
        
        createTables()
    }

    private func execute(sql: String) {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                print("TurnBack DB: Execution failed: \(errorMessage)")
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("TurnBack DB: Statement compilation failed: \(errorMessage)")
        }
        sqlite3_finalize(statement)
    }

    private func createTables() {
        let createSessionsTable = """
        CREATE TABLE IF NOT EXISTS sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            target_duration INTEGER NOT NULL,
            safety_buffer REAL NOT NULL,
            start_time INTEGER NOT NULL,
            end_time INTEGER,
            status TEXT NOT NULL
        );
        """
        
        let createPointsTable = """
        CREATE TABLE IF NOT EXISTS points (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            timestamp INTEGER NOT NULL,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            altitude REAL NOT NULL,
            accuracy REAL NOT NULL,
            speed REAL NOT NULL,
            FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
        );
        """
        
        execute(sql: createSessionsTable)
        execute(sql: createPointsTable)
    }

    func insertPoint(
        sessionId: Int,
        timestamp: Int64,
        lat: Double,
        lng: Double,
        altitude: Double,
        accuracy: Double,
        speed: Double
    ) -> Bool {
        let insertSql = "INSERT INTO points (session_id, timestamp, lat, lng, altitude, accuracy, speed) VALUES (?, ?, ?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertSql, -1, &statement, nil) != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("TurnBack DB: Insert prepare failed: \(errorMessage)")
            return false
        }
        
        sqlite3_bind_int(statement, 1, Int32(sessionId))
        sqlite3_bind_int64(statement, 2, timestamp)
        sqlite3_bind_double(statement, 3, lat)
        sqlite3_bind_double(statement, 4, lng)
        sqlite3_bind_double(statement, 5, altitude)
        sqlite3_bind_double(statement, 6, accuracy)
        sqlite3_bind_double(statement, 7, speed)
        
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        return result
    }
}
