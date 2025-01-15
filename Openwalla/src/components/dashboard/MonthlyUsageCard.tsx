import { MonthlyUsage } from "@/components/MonthlyUsage";
import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import axios from "axios";
import { formatBytes } from "@/utils/networkFormatting";

interface MonthlyData {
  rx: number;
  tx: number;
  interface_name: string;
}

interface Config {
  data_plan_limit: string;
}

export function MonthlyUsageCard() {
  const { data: monthlyData } = useQuery({
    queryKey: ['monthly-usage'],
    queryFn: async () => {
      const response = await axios.get<MonthlyData[]>('/api/vnstat/monthly');
      return response.data;
    },
    refetchInterval: 3600000, // Refresh every hour
  });

  const { data: config } = useQuery({
    queryKey: ['config'],
    queryFn: async () => {
      const response = await axios.get<Config>('/api/config');
      return response.data;
    },
  });

  const calculateTotalUsage = () => {
    if (!monthlyData || monthlyData.length === 0) return 0;
    const total = monthlyData.reduce((acc, curr) => acc + curr.rx + curr.tx, 0);
    console.log('Total monthly usage in bytes:', total, formatBytes(total));
    return total;
  };

  const calculateProgress = () => {
    const totalUsage = calculateTotalUsage();
    if (!config?.data_plan_limit) return 0;
    
    const limitGB = parseFloat(config.data_plan_limit);
    const dataPlanLimit = limitGB * 1000 * 1000 * 1000; // Convert GB to bytes
    const percentage = (totalUsage / dataPlanLimit) * 100;
    
    console.log('Monthly Usage Progress:', {
      totalUsage: formatBytes(totalUsage),
      limit: `${limitGB}GB (${formatBytes(dataPlanLimit)})`,
      percentage: `${percentage.toFixed(2)}%`
    });
    
    return Math.min(Math.round(percentage), 100);
  };

  const getDaysLeft = () => {
    const now = new Date();
    const lastDay = new Date(now.getFullYear(), now.getMonth() + 1, 0);
    return lastDay.getDate() - now.getDate();
  };

  const totalUsage = calculateTotalUsage();
  const interfaceName = monthlyData?.[0]?.interface_name || 'Unknown';
  const progress = calculateProgress();

  return (
    <Link to="/monthly-usage">
      <MonthlyUsage
        title={`${interfaceName} Monthly Usage`}
        value={formatBytes(totalUsage)}
        subtitle={`${getDaysLeft()} days left`}
        progress={progress}
        className="my-4"
      />
    </Link>
  );
}