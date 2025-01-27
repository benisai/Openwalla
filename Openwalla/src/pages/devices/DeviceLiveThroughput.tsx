import { ArrowLeft, Home, RefreshCcw } from "lucide-react";
import { Link } from "react-router-dom";
import { Card } from "@/components/ui/card";
import { Area, AreaChart, ResponsiveContainer, XAxis, YAxis } from "recharts";

const mockDevices = [
  { id: 1, name: "Chromecast", download: 150, upload: 30 },
  { id: 2, name: "Bens-Air", download: 200, upload: 45 },
  { id: 3, name: "Bens-iPad", download: 500, upload: 80 },
  { id: 4, name: "Bens-iPhone", download: 300, upload: 60 },
  { id: 5, name: "DATTO", download: 250, upload: 40 },
  { id: 6, name: "El-CAM", download: 180, upload: 35 },
  { id: 7, name: "LivingRoom-CAM", download: 220, upload: 50 },
  { id: 8, name: "MeLe-WiFi", download: 280, upload: 55 },
  { id: 9, name: "Nest", download: 190, upload: 40 },
  { id: 10, name: "Pixel-7", download: 420, upload: 75 },
];

const DeviceLiveThroughput = () => {
  return (
    <div className="min-h-screen bg-dashboard-background text-white p-4 md:px-0">
      <div className="md:max-w-4xl mx-auto pb-20">
        {/* Header */}
        <header className="flex justify-between items-center mb-6">
          <Link to="/">
            <ArrowLeft className="w-6 h-6 text-dashboard-accent" />
          </Link>
          <div className="flex items-center gap-2">
            <span className="text-xl font-bold">Live Device Throughput</span>
            <RefreshCcw className="w-5 h-5 text-dashboard-accent cursor-pointer" />
          </div>
          <Link to="/">
            <Home className="w-6 h-6 text-dashboard-accent" />
          </Link>
        </header>

        {/* Device Charts */}
        <div className="space-y-4">
          {mockDevices.map((device) => (
            <Card key={device.id} className="bg-dashboard-card p-4">
              <div className="flex items-center justify-between mb-2">
                <h3 className="text-gray-400 text-sm">{device.name}</h3>
                <div className="flex gap-4 text-sm">
                  <span className="text-[#0EA5E9]">{device.download} kb/s ↓</span>
                  <span className="text-[#F97316]">{device.upload} kb/s ↑</span>
                </div>
              </div>
              <div className="h-[60px]">
                <ResponsiveContainer width="100%" height="100%">
                  <AreaChart
                    data={[
                      { time: 1, download: device.download * 0.8, upload: device.upload * 0.7 },
                      { time: 2, download: device.download * 0.9, upload: device.upload * 0.8 },
                      { time: 3, download: device.download * 1.0, upload: device.upload * 1.0 },
                      { time: 4, download: device.download * 0.95, upload: device.upload * 0.9 },
                      { time: 5, download: device.download * 0.85, upload: device.upload * 0.85 },
                    ]}
                  >
                    <XAxis hide />
                    <YAxis hide />
                    <Area
                      type="monotone"
                      dataKey="download"
                      stroke="#0EA5E9"
                      fill="url(#colorDownload)"
                      strokeWidth={2}
                    />
                    <Area
                      type="monotone"
                      dataKey="upload"
                      stroke="#F97316"
                      fill="url(#colorUpload)"
                      strokeWidth={2}
                    />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
            </Card>
          ))}
        </div>
      </div>
    </div>
  );
};

export default DeviceLiveThroughput;