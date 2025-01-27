import { databases } from '../../databases/init';

type DatabaseName = keyof typeof databases;

export class DatabaseService {
  static async query(dbName: DatabaseName, sql: string, params: any[] = []): Promise<any> {
    return new Promise((resolve, reject) => {
      databases[dbName].all(sql, params, (error, rows) => {
        if (error) {
          console.error(`Database error in ${dbName}:`, error);
          reject(error);
        } else {
          resolve(rows);
        }
      });
    });
  }

  static async run(dbName: DatabaseName, sql: string, params: any[] = []): Promise<any> {
    return new Promise((resolve, reject) => {
      databases[dbName].run(sql, params, function(error) {
        if (error) {
          console.error(`Database error in ${dbName}:`, error);
          reject(error);
        } else {
          resolve({ id: this.lastID, changes: this.changes });
        }
      });
    });
  }

  static async getDevices(): Promise<any[]> {
    return this.query('openwrt', 'SELECT * FROM devices');
  }

  static async getNotifications(): Promise<any[]> {
    return this.query('notifications', 'SELECT * FROM notifications ORDER BY detect_time DESC');
  }

  static async getFlows(): Promise<any[]> {
    return this.query('flows', 'SELECT * FROM flow ORDER BY timeinsert DESC LIMIT 100');
  }

  static async getHourlyWanUsage(): Promise<any[]> {
    return this.query('hourlyWanUsage', 'SELECT * FROM hourlywanusage ORDER BY hour ASC');
  }

  static async getPingStats(): Promise<any[]> {
    return this.query('pingStats', 'SELECT * FROM pingstats ORDER BY date DESC, time DESC LIMIT 100');
  }
}