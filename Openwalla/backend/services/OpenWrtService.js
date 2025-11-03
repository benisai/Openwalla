
/**
 * OpenWrtService.js
 * 
 * Service to interact with OpenWrt LuCI API
 * Based on HackApi approach: https://github.com/soif/HackApi
 */
const axios = require('axios');
const { databases } = require('../database/database');

class OpenWrtService {
  constructor(config) {
    this.config = config;
    this.router_ip = config.router_ip;
    this.luci_port = config.luci_port;
    this.baseUrl = this.buildBaseUrl();
    this.username = config.openwrt_user;
    this.password = config.openwrt_pass;
    this.sessionCookie = null;
    this.axiosInstance = null;
    console.log('OpenWrtService initialized with config:', {
      router_ip: this.router_ip,
      luci_port: this.luci_port,
      baseUrl: this.baseUrl,
      username: this.username ? '[SET]' : '[NOT SET]',
      password: this.password ? '[SET]' : '[NOT SET]'
    });
    this.initializeAxios();
  }

  /**
   * Build the base URL with optional port
   */
  buildBaseUrl() {
    if (this.luci_port && this.luci_port.trim() !== '') {
      const url = `http://${this.router_ip}:${this.luci_port}`;
      console.log('Built base URL with port:', url);
      return url;
    }
    const url = `http://${this.router_ip}`;
    console.log('Built base URL without port:', url);
    return url;
  }

  /**
   * Initialize axios instance with cookie jar for session management
   */
  initializeAxios() {
    this.axiosInstance = axios.create({
      baseURL: this.baseUrl,
      timeout: 10000,
      withCredentials: true,
    });
    console.log('Axios instance initialized with baseURL:', this.baseUrl);
  }

  /**
   * Extract CSRF token from HTML response
   */
  extractCSRFToken(html) {
    // Look for token in various places in the HTML
    const tokenPatterns = [
      /name="token"\s+value="([^"]+)"/,
      /name="luci_token"\s+value="([^"]+)"/,
      /"token":\s*"([^"]+)"/,
      /L\.env\.token\s*=\s*["']([^"']+)["']/
    ];
    
    for (const pattern of tokenPatterns) {
      const match = html.match(pattern);
      if (match) {
        console.log('Found CSRF token using pattern:', pattern.source);
        return match[1];
      }
    }
    
    console.log('No CSRF token found in HTML response');
    return null;
  }

  /**
   * Authenticate with OpenWrt using LuCI login
   */
  async authenticate() {
    try {
      console.log('Authenticating with OpenWrt LuCI');
      
      if (!this.username || !this.password) {
        console.log('No OpenWrt credentials configured');
        return false;
      }

      // First, get the login page to establish session and get any required tokens
      const loginPageUrl = '/cgi-bin/luci';
      const fullLoginPageUrl = `${this.baseUrl}${loginPageUrl}`;
      console.log('Attempting to access login page at:', fullLoginPageUrl);
      
      const loginPageResponse = await this.axiosInstance.get(loginPageUrl, {
        validateStatus: (status) => status < 500 // Accept 403 as it's expected for login page
      });
      console.log('Login page response status:', loginPageResponse.status);
      console.log('Login page response headers:', loginPageResponse.headers);
      
      // Extract cookies from response
      const cookies = loginPageResponse.headers['set-cookie'];
      if (cookies) {
        this.sessionCookie = cookies.join('; ');
        console.log('Session cookies received:', this.sessionCookie);
      } else {
        console.log('No session cookies received from login page');
      }

      // Extract CSRF token if present
      const csrfToken = this.extractCSRFToken(loginPageResponse.data);
      console.log('CSRF token extracted:', csrfToken ? '[FOUND]' : '[NOT FOUND]');

      // Try different authentication endpoints and methods
      const authEndpoints = [
        '/cgi-bin/luci',
        '/cgi-bin/luci/admin',
        '/cgi-bin/luci/admin/index',
        '/cgi-bin/luci/admin/sysauth'
      ];

      for (const endpoint of authEndpoints) {
        console.log(`\n--- Trying authentication with endpoint: ${endpoint} ---`);
        const fullAuthUrl = `${this.baseUrl}${endpoint}`;
        console.log('Full authentication URL:', fullAuthUrl);

        try {
          // Prepare login data
          const loginData = new URLSearchParams({
            luci_username: this.username,
            luci_password: this.password
          });

          // Add CSRF token if we found one
          if (csrfToken) {
            loginData.append('token', csrfToken);
            loginData.append('luci_token', csrfToken);
          }

          console.log('Login data prepared:', loginData.toString());

          // Perform login
          const loginResponse = await this.axiosInstance.post(endpoint, loginData, {
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Cookie': this.sessionCookie || '',
              'Referer': fullLoginPageUrl
            },
            maxRedirects: 0,
            validateStatus: (status) => status < 400
          });

          console.log('Login response status:', loginResponse.status);
          console.log('Login response headers:', loginResponse.headers);

          // Check if login was successful
          const newCookies = loginResponse.headers['set-cookie'];
          if (newCookies) {
            this.sessionCookie = newCookies.join('; ');
            console.log('Updated session cookies:', this.sessionCookie);
          }

          // Check for successful authentication indicators
          const isRedirect = loginResponse.status >= 300 && loginResponse.status < 400;
          const hasAuthCookie = this.sessionCookie && this.sessionCookie.includes('sysauth');
          const noLoginRequired = !loginResponse.headers['x-luci-login-required'];
          
          console.log('Authentication check - Redirect:', isRedirect, 'Auth Cookie:', hasAuthCookie, 'No Login Required:', noLoginRequired);

          if (isRedirect || hasAuthCookie || noLoginRequired) {
            console.log(`Successfully authenticated with OpenWrt using endpoint: ${endpoint}`);
            return true;
          }

        } catch (endpointError) {
          console.log(`Failed to authenticate with endpoint ${endpoint}:`, endpointError.message);
          continue; // Try next endpoint
        }
      }

      console.log('Authentication failed with all attempted endpoints');
      return false;
    } catch (error) {
      console.error('Error authenticating with OpenWrt:', error.message);
      console.error('Error details:', {
        code: error.code,
        response: error.response ? {
          status: error.response.status,
          statusText: error.response.statusText,
          headers: error.response.headers,
          data: typeof error.response.data === 'string' ? error.response.data.substring(0, 500) + '...' : error.response.data
        } : 'No response'
      });
      return false;
    }
  }

  /**
   * Make authenticated request to OpenWrt API
   */
  async makeAuthenticatedRequest(endpoint, method = 'GET', data = null) {
    try {
      // Try authentication first
      const isAuthenticated = await this.authenticate();
      if (!isAuthenticated) {
        throw new Error('Authentication failed');
      }

      const fullUrl = `${this.baseUrl}${endpoint}`;
      console.log(`Making authenticated ${method} request to:`, fullUrl);

      const config = {
        method,
        url: endpoint,
        headers: {
          'Cookie': this.sessionCookie || ''
        }
      };

      if (data && method !== 'GET') {
        config.data = data;
        config.headers['Content-Type'] = 'application/json';
      }

      const response = await this.axiosInstance(config);
      console.log('Authenticated request response status:', response.status);
      return response.data;
    } catch (error) {
      console.error(`Error making request to ${endpoint}:`, error.message);
      throw error;
    }
  }

  /**
   * Get system information
   */
  async getSystemInfo() {
    try {
      const response = await this.makeAuthenticatedRequest('/cgi-bin/luci/admin/status/overview');
      
      // Parse the response to extract system info
      // This would need to be adapted based on the actual HTML/JSON response format
      return {
        hostname: 'OpenWrt Router',
        uptime: 'Unknown',
        load: 'Unknown',
        memory: 'Unknown'
      };
    } catch (error) {
      throw new Error(`Failed to get system info: ${error.message}`);
    }
  }

  /**
   * Get network interfaces using UCI
   */
  async getNetworkInterfaces() {
    try {
      const response = await this.makeAuthenticatedRequest('/cgi-bin/luci/admin/uci');
      return response;
    } catch (error) {
      throw new Error(`Failed to get network interfaces: ${error.message}`);
    }
  }

  /**
   * Get wireless configuration
   */
  async getWirelessConfig() {
    try {
      const response = await this.makeAuthenticatedRequest('/cgi-bin/luci/admin/network/wireless');
      return response;
    } catch (error) {
      throw new Error(`Failed to get wireless config: ${error.message}`);
    }
  }

  /**
   * Test the connection to OpenWrt
   */
  async testConnection() {
    try {
      // Simple test - try to access the main page
      const testUrl = '/cgi-bin/luci';
      const fullTestUrl = `${this.baseUrl}${testUrl}`;
      console.log('Testing connection to:', fullTestUrl);
      
      const response = await this.axiosInstance.get(testUrl, {
        timeout: 5000,
        validateStatus: (status) => status < 500 // Accept 403 as it indicates the server is reachable
      });
      
      console.log('Test connection response status:', response.status);
      console.log('Test connection response headers:', response.headers);
      
      if (response.status === 200 || response.status === 403) {
        console.log('Router is reachable, attempting authentication...');
        // Try authentication
        const authResult = await this.authenticate();
        const result = {
          success: authResult,
          message: authResult ? 'Connection and authentication successful' : 'Connection successful but authentication failed',
          details: {
            reachable: true,
            authenticated: authResult,
            responseStatus: response.status,
            luciLoginRequired: response.headers['x-luci-login-required'] === 'yes'
          }
        };
        console.log('Final test result:', result);
        return result;
      }
      
      const result = {
        success: false,
        message: `Router responded with status ${response.status}`,
        details: {
          reachable: true,
          authenticated: false,
          responseStatus: response.status
        }
      };
      console.log('Test failed - unexpected status:', result);
      return result;
    } catch (error) {
      console.error('Connection test failed with error:', error.message);
      console.error('Error details:', {
        code: error.code,
        response: error.response ? {
          status: error.response.status,
          statusText: error.response.statusText,
          headers: error.response.headers
        } : 'No response'
      });
      
      const result = {
        success: false,
        message: `Connection failed: ${error.message}`,
        details: {
          reachable: false,
          authenticated: false,
          error: error.message,
          errorCode: error.code
        }
      };
      console.log('Final error result:', result);
      return result;
    }
  }

  /**
   * Get router status information
   */
  async getRouterStatus() {
    try {
      const isAuthenticated = await this.authenticate();
      if (!isAuthenticated) {
        throw new Error('Authentication required');
      }

      // Get basic router information
      const statusResponse = await this.makeAuthenticatedRequest('/cgi-bin/luci/admin/status/overview');
      
      return {
        connected: true,
        authenticated: true,
        response: 'Router is accessible and authenticated'
      };
    } catch (error) {
      return {
        connected: false,
        authenticated: false,
        error: error.message
      };
    }
  }
}

module.exports = OpenWrtService;
