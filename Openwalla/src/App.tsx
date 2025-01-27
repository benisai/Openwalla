import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import Index from "./pages/dashboard/Index";
import NetworkPerformance from "./pages/network_performance/Network_Performance";
import Flows from "./pages/flows/Flows";
import BlockedFlows from "./pages/flows/BlockedFlows";
import Settings from "./pages/settings/Settings";
import MonthlyUsage from "./pages/monthly-usage/MonthlyUsage";
import Devices from "./pages/devices/Devices";
import DeviceDetails from "./pages/devices/DeviceDetails";
import DeviceLiveThroughput from "./pages/devices/DeviceLiveThroughput";
import NotificationsPage from "./pages/notifications/NotificationsPage";
import DeviceFlows from "./pages/devices/DeviceFlows";
import Rules from "./pages/rules/Rules";
import RecentEvents from "./pages/network_performance/RecentEvents";

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
          <Route path="/recent-events" element={<RecentEvents />} />
        </Routes>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;