import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ChevronRight, Globe } from "lucide-react";
import { LineChart, Line, XAxis, YAxis, CartesianGrid, ResponsiveContainer } from 'recharts';
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";

export function InternetQualityCard() {
  const navigate = useNavigate();

  const { data: pingStats = [], isLoading } = useQuery({
    queryKey: ['ping-stats'],
    queryFn: async () => {
      const response = await fetch('/api/ping-stats/last24hours');
      if (!response.ok) {
        throw new Error('Failed to fetch ping stats');
      }
      const data = await response.json();
      return data.slice(-10);
    },
    refetchInterval: 60000
  });

  const maxLatency = Math.max(...(pingStats?.map((stat: any) => stat.median_latency || 0) || [0]));
  const medianLatency = pingStats?.length > 0 
    ? [...pingStats].sort((a, b) => (a.median_latency || 0) - (b.median_latency || 0))[Math.floor(pingStats.length / 2)]?.median_latency || 0
    : 0;

  const chartData = pingStats?.map((stat: any) => ({
    time: new Date(stat.date + ' ' + stat.time).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
    latency: stat.median_latency || 0
  })).reverse() || [];

  return (
    <Card className="bg-dashboard-card text-white">
      <CardHeader className="flex flex-row items-center justify-between">
        <div className="flex items-center gap-2">
          <Globe className="h-5 w-5" />
          <CardTitle className="text-xl">Internet Quality</CardTitle>
        </div>
        <div 
          className="flex items-center gap-2 cursor-pointer"
          onClick={() => navigate("/settings")}
        >
          <span className="text-blue-400">Test Options</span>
          <ChevronRight className="h-5 w-5 text-gray-400" />
        </div>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="grid grid-cols-2 gap-4">
          <div>
            <div className="flex items-center gap-2">
              <span className="text-gray-400">Max Latency</span>
            </div>
            <p className="text-base md:text-2xl font-bold">
              {isLoading ? "Loading..." : `${maxLatency.toFixed(1)} ms`}
            </p>
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="text-gray-400">Median Latency</span>
            </div>
            <p className="text-base md:text-2xl font-bold">
              {isLoading ? "Loading..." : `${medianLatency.toFixed(1)} ms`}
            </p>
          </div>
        </div>
        <div className="h-64 w-full">
          {isLoading ? (
            <div className="flex items-center justify-center h-full">
              <p>Loading data...</p>
            </div>
          ) : (
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
                <XAxis 
                  dataKey="time" 
                  stroke="#9CA3AF"
                  tickFormatter={(value) => value}
                />
                <YAxis 
                  stroke="#9CA3AF" 
                  domain={[0, Math.max(30, maxLatency + 10)]}
                  ticks={[0, Math.round(maxLatency/3), Math.round(maxLatency*2/3), maxLatency]}
                />
                <Line 
                  type="monotone" 
                  dataKey="latency" 
                  stroke="#3B82F6" 
                  strokeWidth={2} 
                  dot={{ fill: "#3B82F6", r: 4 }} 
                />
              </LineChart>
            </ResponsiveContainer>
          )}
        </div>
      </CardContent>
    </Card>
  );
}