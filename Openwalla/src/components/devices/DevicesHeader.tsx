import { ArrowLeft, Home } from "lucide-react";
import { Link } from "react-router-dom";

const DevicesHeader = () => {
  return (
    <header className="flex justify-between items-center mb-6">
      <Link to="/">
        <ArrowLeft className="w-6 h-6 text-dashboard-accent" />
      </Link>
      <div className="flex items-center gap-2">
        <span className="text-xl font-bold">Devices</span>
      </div>
      <Link to="/">
        <Home className="w-6 h-6 text-dashboard-accent" />
      </Link>
    </header>
  );
};

export default DevicesHeader;