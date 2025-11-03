
const { formatBytes } = require('../../utils/networkFormatting');

class DataAggregator {
  constructor(db) {
    this.db = db;
    this.processedRecords = 0;
    this.skippedRecords = 0;
    this.updatedRecords = 0;
    this.insertedRecords = 0;
    this.errorRecords = 0;
  }

  async aggregateFlowData() {
    try {
      //console.log('Starting flow data aggregation with unique digest filtering...');
      // Reset counters for this aggregation cycle
      this.processedRecords = 0;
      this.skippedRecords = 0;
      this.updatedRecords = 0;
      this.insertedRecords = 0;
      this.errorRecords = 0;
      
      // Query recent flows with their stats
      const query = `
        SELECT 
          f.local_mac,
          f.hostname,
          f.detected_app_name,
          strftime('%Y-%m-%d %H:00:00', f.timeinsert) as timeperiod,
          f.digest,
          sp.local_bytes + sp.other_bytes as total_bytes,
          sp.local_bytes as upload_bytes,
          sp.other_bytes as download_bytes,
          sp.local_packets + sp.other_packets as total_packets,
          1 as flow_count
        FROM flow f
        INNER JOIN stats_purge sp ON f.digest = sp.digest
        WHERE f.timeinsert > datetime('now', '-60 seconds')
        AND sp.timeinsert > datetime('now', '-60 seconds');
      `;

      const rows = await this.queryDatabase(query, []);
      //console.log(`Found ${rows.length} matching records to process from last 60 seconds`);

      // Process each record individually to ensure unique digest handling
      for (const row of rows) {
        try {
          this.processedRecords++;
          await this.processRecord(row);
        } catch (error) {
          this.errorRecords++;
          console.error('Error processing record:', error);
        }
      }

      //console.log(`Processing summary: Processed=${this.processedRecords}, Inserted=${this.insertedRecords}, Updated=${this.updatedRecords}, Skipped=${this.skippedRecords}, Errors=${this.errorRecords}`);

    } catch (error) {
      console.error('Error in aggregateFlowData:', error);
      throw error;
    }
  }

  async processRecord(record) {
    try {
      // Check if this digest already exists
      const existingRecord = await this.getExistingRecordByDigest(record.digest);
      
      if (existingRecord) {
        this.skippedRecords++;
        //console.log(`Skipping duplicate digest: ${record.digest}`);
        return;
      }
      
      // Insert as a new record since digest is unique
      await this.insertNewRecord(record);
      this.insertedRecords++;
      
    } catch (error) {
      console.error('Error in processRecord:', error);
      throw error;
    }
  }

  async queryDatabase(query, params) {
    return new Promise((resolve, reject) => {
      this.db.all(query, params, (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  async getExistingRecordByDigest(digest) {
    return new Promise((resolve, reject) => {
      this.db.get(
        `SELECT * FROM application_usage WHERE digest = ?`,
        [digest],
        (err, result) => {
          if (err) reject(err);
          else resolve(result);
        }
      );
    });
  }

  async insertNewRecord(record) {
    return new Promise((resolve, reject) => {
      const insertQuery = `
        INSERT INTO application_usage (
          timeinsert,
          local_mac,
          hostname,
          detected_app_name,
          timeperiod,
          digest,
          total_bytes,
          upload_bytes,
          download_bytes,
          total_packets,
          flow_count,
          last_updated
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, strftime('%s', 'now'))
      `;
      
      const params = [
        new Date().toISOString(),
        record.local_mac,
        record.hostname,
        record.detected_app_name,
        record.timeperiod,
        record.digest,
        record.total_bytes,
        record.upload_bytes,
        record.download_bytes,
        record.total_packets,
        record.flow_count
      ];

      this.db.run(insertQuery, params, function(err) {
        if (err) {
          // If it's a UNIQUE constraint error, we can ignore it (another thread might have inserted it)
          if (err.message.includes('UNIQUE constraint failed')) {
            console.log(`Digest ${record.digest} already inserted by another thread`);
            resolve();
          } else {
            console.error(`Failed to insert record with digest ${record.digest}`);
            console.error('Insert error:', err);
            reject(err);
          }
        } else {
          //console.log(`Inserted new record with ID ${this.lastID} for digest ${record.digest}`);
          resolve();
        }
      });
    });
  }
}

module.exports = DataAggregator;
