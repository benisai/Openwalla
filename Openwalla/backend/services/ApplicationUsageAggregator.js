
const path = require('path');
const sqlite3 = require('sqlite3');
const DataAggregator = require('./aggregation/DataAggregator');

class ApplicationUsageAggregator {
  constructor(config) {
    this.config = config;
    this.aggregationInterval = null;
    this.isRunning = false;
    this.db = null;
    this.databaseDir = this.config.database_dir || path.join(__dirname, '../../databases');
    this.dataAggregator = null;
  }

  async start() {
    if (this.isRunning) return;
    
    console.log('Starting Application Usage Aggregator service...');
    this.isRunning = true;
    
    try {
      // Connect to database directly
      await this.connectToDatabase('flows.sqlite');
      
      // Initialize DataAggregator with local time option
      this.dataAggregator = new DataAggregator(this.db, { useLocalTime: true });

      // Run initial aggregation
      await this.aggregate();
      
      // Schedule regular aggregation
      this.aggregationInterval = setInterval(
        () => this.aggregate(),
        1 * 60 * 1000 // 1 minute
      );
    } catch (error) {
      console.error('Failed to start ApplicationUsageAggregator:', error);
      this.stop();
    }
  }

  connectToDatabase(dbName) {
    return new Promise((resolve, reject) => {
      const dbPath = path.join(this.databaseDir, dbName);
      const db = new sqlite3.Database(
        dbPath,
        sqlite3.OPEN_READWRITE,
        (err) => {
          if (err) {
            console.error(`Error connecting to ${dbPath}:`, err);
            reject(err);
            return;
          }
          this.db = db;
          resolve();
        }
      );
    });
  }

  async stop() {
    if (this.aggregationInterval) {
      clearInterval(this.aggregationInterval);
    }
    if (this.db) {
      this.db.close();
    }
    this.isRunning = false;
  }

  async aggregate() {
    console.log('Running application usage aggregation with local time...');
    const startTime = Date.now();

    try {
      // Pass local time flag to ensure consistent time format with NetifyFlowProcessor
      await this.dataAggregator.aggregateFlowData({ useLocalTime: true });
      
      console.log(`Aggregation completed in ${Date.now() - startTime}ms`);
    } catch (error) {
      console.error('Error during aggregation:', error);
    }
  }
}

module.exports = ApplicationUsageAggregator;
