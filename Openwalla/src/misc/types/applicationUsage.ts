
export interface ApplicationUsage {
  deviceMac: string;
  deviceName: string;
  totalUsage: number;
  applications: {
    name: string;
    bytesUsed: number;
    percentage: number;
  }[];
  timelineData: {
    hour: number;
    usage: number;
  }[];
}
