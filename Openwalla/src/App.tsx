import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import ProtectedRoute from "@/components/auth/ProtectedRoute";
import { NotificationToastManager } from "@/components/notifications/NotificationToastManager";
import Login from "@/pages/auth/Login";
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
import ApplicationUsage from "./pages/application-usage/ApplicationUsage";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <NotificationToastManager />
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route path="/" element={<ProtectedRoute><Index /></ProtectedRoute>} />
          <Route path="/network-performance" element={<ProtectedRoute><NetworkPerformance /></ProtectedRoute>} />
          <Route path="/flows" element={<ProtectedRoute><Flows /></ProtectedRoute>} />
          <Route path="/blocked-flows" element={<ProtectedRoute><BlockedFlows /></ProtectedRoute>} />
          <Route path="/settings" element={<ProtectedRoute><Settings /></ProtectedRoute>} />
          <Route path="/monthly-usage" element={<ProtectedRoute><MonthlyUsage /></ProtectedRoute>} />
          <Route path="/devices" element={<ProtectedRoute><Devices /></ProtectedRoute>} />
          <Route path="/devices/:id" element={<ProtectedRoute><DeviceDetails /></ProtectedRoute>} />
          <Route path="/device-live-throughput" element={<ProtectedRoute><DeviceLiveThroughput /></ProtectedRoute>} />
          <Route path="/notifications" element={<ProtectedRoute><NotificationsPage /></ProtectedRoute>} />
          <Route path="/device-flows/:mac" element={<ProtectedRoute><DeviceFlows /></ProtectedRoute>} />
          <Route path="/rules" element={<ProtectedRoute><Rules /></ProtectedRoute>} />
          <Route path="/recent-events" element={<ProtectedRoute><RecentEvents /></ProtectedRoute>} />
          <Route path="/application-usage" element={<ProtectedRoute><ApplicationUsage /></ProtectedRoute>} />
        </Routes>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;
