import { LayoutDashboard, Settings } from "lucide-react";
import { Link, useLocation } from "react-router-dom";

const BottomNav = () => {
  const location = useLocation();
  const isSettings = location.pathname === "/settings";

  return (
    <nav className="fixed bottom-0 left-0 right-0 bg-dashboard-card border-t border-gray-800 p-4">
      <div className="flex justify-around max-w-lg mx-auto">
        <Link to="/">
          <LayoutDashboard className={`w-6 h-6 ${isSettings ? 'text-gray-500' : 'text-dashboard-accent'}`} />
        </Link>
        <Link to="/settings">
          <Settings className={`w-6 h-6 ${isSettings ? 'text-dashboard-accent' : 'text-gray-500'}`} />
        </Link>
      </div>
    </nav>
  );
};

export default BottomNav;