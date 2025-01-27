import { Card } from "@/components/ui/card";
import { useQuery } from "@tanstack/react-query";
import { formatBytes } from "@/misc/utils/networkFormatting";

export function UsageStats() {
  const { data: dailyData = [] } = useQuery({
    queryKey: ['vnstat-daily'],
    queryFn: async () => {
      const response = await fetch('/api/vnstat/daily');
      if (!response.ok) {
        throw new Error('Network response was not ok');
      }
      return response.json();
    },
    refetchInterval: 60 * 60 * 1000, // Refetch every hour
  });

  const calculateTotal = () => {
    return dailyData.reduce((acc: number, curr: any) => acc + curr.rx + curr.tx, 0);
  };

  const calculateDailyAverage = () => {
    if (dailyData.length === 0) return 0;
    return calculateTotal() / dailyData.length;
  };

  const getMonthText = () => {
    if (dailyData.length === 0) return "No data available";
    const date = new Date();
    const monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    const month = monthNames[date.getMonth()];
    const lastDay = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate();
    return `${month} 01 - ${lastDay}, ${date.getFullYear()}`;
  };

  return (
    <div className="grid grid-cols-2 gap-4 mb-8">
      <Card className="bg-dashboard-card p-4">
        <p className="text-gray-400 mb-2">Daily Average</p>
        <p className="text-2xl font-bold">{formatBytes(calculateDailyAverage())}</p>
      </Card>
      <Card className="bg-dashboard-card p-4">
        <p className="text-gray-400 mb-2">Total, {getMonthText()}</p>
        <p className="text-2xl font-bold">{formatBytes(calculateTotal())}</p>
      </Card>
    </div>
  );
}