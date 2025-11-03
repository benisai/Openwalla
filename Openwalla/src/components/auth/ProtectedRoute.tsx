
import { useEffect, useState } from "react";
import { Navigate } from "react-router-dom";
import AuthService from "@/services/AuthService";

interface ProtectedRouteProps {
  children: React.ReactNode;
}

const ProtectedRoute = ({ children }: ProtectedRouteProps) => {
  const [isChecking, setIsChecking] = useState(true);
  const [isAuthenticated, setIsAuthenticated] = useState(false);

  useEffect(() => {
    const checkAuth = async () => {
      if (AuthService.isAuthenticated()) {
        const isValid = await AuthService.verifyToken();
        setIsAuthenticated(isValid);
      } else {
        setIsAuthenticated(false);
      }
      setIsChecking(false);
    };

    checkAuth();
  }, []);

  if (isChecking) {
    return (
      <div className="min-h-screen bg-dashboard-background flex items-center justify-center">
        <div className="text-white">Verifying authentication...</div>
      </div>
    );
  }

  return isAuthenticated ? <>{children}</> : <Navigate to="/login" replace />;
};

export default ProtectedRoute;
