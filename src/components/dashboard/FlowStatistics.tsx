import { Flows24 } from "@/components/dashboard/Flows24";
import { Blocked24 } from "@/components/dashboard/Blocked24";

export function FlowStatistics() {
  return (
    <div className="flow-statistics-section">
      <div className="grid grid-cols-2 gap-4 mb-4">
        <div className="flow-card">
          <Flows24 />
        </div>
        <div className="blocked-card">
          <Blocked24 />
        </div>
      </div>
    </div>
  );
}