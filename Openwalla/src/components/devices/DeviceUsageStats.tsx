import { formatBytes } from "@/utils/networkFormatting";
import { Device } from "@/types/device";

interface DeviceUsageStatsProps {
  device: Device;
}

export function DeviceUsageStats({ device }: DeviceUsageStatsProps) {
  return (
    <div className="bg-dashboard-card rounded-lg p-4 space-y-6">
      <div className="flex justify-between">
        <div>
          <p className="text-gray-400">Total Download</p>
          <p className="text-2xl font-bold">{formatBytes(device.total_download)}</p>
        </div>
        <div className="text-right">
          <p className="text-gray-400">Total Upload</p>
          <p className="text-2xl font-bold">{formatBytes(device.total_upload)}</p>
        </div>
      </div>
    </div>
  );
}