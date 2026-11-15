package org.opensource.tracker.data.db

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface TrackDao {
    @Query("SELECT * FROM tracks ORDER BY startTime DESC")
    fun getAllTracks(): Flow<List<TrackEntity>>

    @Query("SELECT * FROM tracks ORDER BY startTime DESC")
    suspend fun getAllTracksList(): List<TrackEntity>

    @Query("SELECT * FROM tracks WHERE id = :id")
    suspend fun getTrackById(id: Long): TrackEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertTrack(track: TrackEntity): Long

    @Update
    suspend fun updateTrack(track: TrackEntity)

    @Delete
    suspend fun deleteTrack(track: TrackEntity)
}

@Dao
interface WaypointDao {
    @Query("SELECT * FROM waypoints WHERE trackId = :trackId ORDER BY timestamp ASC")
    fun getWaypointsForTrack(trackId: Long): Flow<List<WaypointEntity>>

    @Query("SELECT * FROM waypoints WHERE trackId = :trackId ORDER BY timestamp ASC")
    suspend fun getWaypointsList(trackId: Long): List<WaypointEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertWaypoints(waypoints: List<WaypointEntity>)

    @Delete
    suspend fun deleteWaypoint(waypoint: WaypointEntity)
}

@Database(
    entities = [TrackEntity::class, WaypointEntity::class],
    version = 1,
    exportSchema = false,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun trackDao(): TrackDao

    abstract fun waypointDao(): WaypointDao

    companion object {
        @Volatile
        private var instance: AppDatabase? = null

        fun getInstance(context: Context): AppDatabase =
            instance ?: synchronized(this) {
                val newInstance =
                    Room
                        .databaseBuilder(
                            context.applicationContext,
                            AppDatabase::class.java,
                            "turnback_compose.db",
                        ).fallbackToDestructiveMigration()
                        .build()
                instance = newInstance
                newInstance
            }
    }
}
