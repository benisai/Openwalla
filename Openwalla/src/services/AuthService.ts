
interface LoginResponse {
  success: boolean;
  token?: string;
  user?: {
    id: number;
    username: string;
  };
  error?: string;
}

interface User {
  id: number;
  username: string;
}

class AuthService {
  private static TOKEN_KEY = 'openwalla_auth_token';
  private static USER_KEY = 'openwalla_user';

  static async login(username: string, password: string): Promise<LoginResponse> {
    try {
      const response = await fetch('/api/auth/login', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ username, password }),
      });

      const data = await response.json();

      if (data.success && data.token) {
        localStorage.setItem(this.TOKEN_KEY, data.token);
        localStorage.setItem(this.USER_KEY, JSON.stringify(data.user));
      }

      return data;
    } catch (error) {
      console.error('Login error:', error);
      return { success: false, error: 'Network error' };
    }
  }

  static async verifyToken(): Promise<boolean> {
    const token = localStorage.getItem(this.TOKEN_KEY);
    if (!token) return false;

    try {
      const response = await fetch('/api/auth/verify', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ token }),
      });

      const data = await response.json();
      
      if (data.success) {
        localStorage.setItem(this.USER_KEY, JSON.stringify(data.user));
        return true;
      } else {
        this.logout();
        return false;
      }
    } catch (error) {
      console.error('Token verification error:', error);
      this.logout();
      return false;
    }
  }

  static logout(): void {
    localStorage.removeItem(this.TOKEN_KEY);
    localStorage.removeItem(this.USER_KEY);
  }

  static isAuthenticated(): boolean {
    return !!localStorage.getItem(this.TOKEN_KEY);
  }

  static getCurrentUser(): User | null {
    const userStr = localStorage.getItem(this.USER_KEY);
    return userStr ? JSON.parse(userStr) : null;
  }

  static getToken(): string | null {
    return localStorage.getItem(this.TOKEN_KEY);
  }
}

export default AuthService;
