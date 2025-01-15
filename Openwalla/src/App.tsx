import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import Index from "./pages/Index";
import NetworkPerformance from "./pages/Network_Performance";
import Flows from "./pages/Flows";
import BlockedFlows from "./pages/BlockedFlows";
import Settings from "./pages/Settings";
import MonthlyUsage from "./pages/MonthlyUsage";
import Devices from "./pages/Devices";
import DeviceDetails from "./pages/DeviceDetails";
import DeviceLiveThroughput from "./pages/DeviceLiveThroughput";
import NotificationsPage from "./pages/NotificationsPage";
import DeviceFlows from "./pages/DeviceFlows";
import Rules from "./pages/Rules";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<Index />} />
          <Route path="/network-performance" element={<NetworkPerformance />} />
          <Route path="/flows" element={<Flows />} />
          <Route path="/blocked-flows" element={<BlockedFlows />} />
          <Route path="/settings" element={<Settings />} />
          <Route path="/monthly-usage" element={<MonthlyUsage />} />
          <Route path="/devices" element={<Devices />} />
          <Route path="/devices/:id" element={<DeviceDetails />} />
          <Route path="/device-live-throughput" element={<DeviceLiveThroughput />} />
          <Route path="/notifications" element={<NotificationsPage />} />
          <Route path="/device-flows/:mac" element={<DeviceFlows />} />
          <Route path="/rules" element={<Rules />} />
        </Routes>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;