import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ChevronRight, Globe, ArrowDown, ArrowUp } from "lucide-react";
import { LineChart, Line, XAxis, YAxis, CartesianGrid, ResponsiveContainer } from 'recharts';
import { WANTestOptions } from "./WANTestOptions";
import { useState } from "react";

const data = [
  { name: 'Sun', download: 800, upload: 40 },
  { name: 'Mon', download: 700, upload: 38 },
  { name: 'Tue', download: 500, upload: 35 },
  { name: 'Wed', download: 550, upload: 37 },
  { name: 'Thu', download: 300, upload: 36 },
  { name: 'Fri', download: 200, upload: 35 },
  { name: 'Sat', download: 900, upload: 39 },
];

export function InternetSpeedCard() {
  const [isTestOptionsOpen, setIsTestOptionsOpen] = useState(false);

  return (
    <Card className="bg-dashboard-card text-white">
      <CardHeader className="flex flex-row items-center justify-between">
        <div className="flex items-center gap-2">
          <Globe className="h-5 w-5" />
          <CardTitle className="text-xl">WAN</CardTitle>
        </div>
        <div 
          className="flex items-center gap-2 cursor-pointer"
          onClick={() => setIsTestOptionsOpen(true)}
        >
          <span className="text-blue-400">Test Options</span>
          <ChevronRight className="h-5 w-5 text-gray-400" />
        </div>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="grid grid-cols-2 gap-4">
          <div>
            <div className="flex items-center gap-2">
              <ArrowDown className="h-4 w-4 text-blue-400" />
              <span className="text-gray-400">Download</span>
            </div>
            <p className="text-base md:text-2xl font-bold">913.71 Mb/s</p>
          </div>
          <div>
            <div className="flex items-center gap-2">
              <ArrowUp className="h-4 w-4 text-red-400" />
              <span className="text-gray-400">Upload</span>
            </div>
            <p className="text-base md:text-2xl font-bold">38.89 Mb/s</p>
          </div>
        </div>
        <p className="text-sm text-gray-400">Last speed test at Jan 04 08:05 AM</p>
        <div className="h-64 w-full">
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={data}>
              <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
              <XAxis dataKey="name" stroke="#9CA3AF" />
              <YAxis stroke="#9CA3AF" />
              <Line type="monotone" dataKey="download" stroke="#3B82F6" strokeWidth={2} dot={{ fill: "#3B82F6" }} />
              <Line type="monotone" dataKey="upload" stroke="#EF4444" strokeWidth={2} dot={{ fill: "#EF4444" }} />
            </LineChart>
          </ResponsiveContainer>
        </div>
        <button className="w-full py-2 text-blue-400 hover:text-blue-300 transition-colors">
          Test Internet Speed
        </button>
      </CardContent>

      <WANTestOptions 
        open={isTestOptionsOpen}
        onOpenChange={setIsTestOptionsOpen}
      />
    </Card>
  );
}