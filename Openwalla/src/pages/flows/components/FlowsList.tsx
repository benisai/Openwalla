import { format } from "date-fns";
import { Flow } from "@/misc/types/flow";
import { useIsMobile } from "@/hooks/use-mobile";

interface FlowsListProps {
  flows: Flow[];
  onFlowClick: (flow: Flow) => void;
}

export const FlowsList = ({ flows, onFlowClick }: FlowsListProps) => {
  const isMobile = useIsMobile();

  const truncateHost = (host: string) => {
    const maxLength = isMobile ? 35 : 140;
    if (!host || host.length <= maxLength) return host || '';
    return '...' + host.slice(-maxLength);
  };

  return (
    <div className="space-y-2">
      {flows.map((flow, index) => (
        <div
          key={index}
          className="flex items-center gap-3 py-2 border-b border-gray-800 cursor-pointer hover:bg-gray-800/50"
          onClick={() => onFlowClick(flow)}
        >
          <div className="flex-shrink-0 text-gray-400 text-sm whitespace-nowrap">
            {format(new Date(flow.timeinsert), 'h:mm a')}
          </div>
          <span className="flex-shrink-0 text-gray-400 flex items-center">•</span>
          <div className="flex items-start gap-2 min-w-0">
            <span className="flex-shrink-0 text-sm">
              {flow.internal ? "🖥" : "🌐"}
            </span>
            <span className="text-sm break-all">
              {truncateHost(flow.fqdn || flow.dest_ip)}
            </span>
          </div>
        </div>
      ))}
    </div>
  );
};