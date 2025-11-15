#!/bin/bash

# Define script root directory
SCRIPT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Define backend and frontend paths
BACKEND_PATH="$SCRIPT_ROOT/backend"
FRONTEND_PATH="$SCRIPT_ROOT/src"

# Define logs directory
LOGS_DIR="$SCRIPT_ROOT/logs"

# Create logs directory if it doesn't exist
mkdir -p "$LOGS_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# PID files
BACKEND_PID_FILE="$SCRIPT_ROOT/backend.pid"
FRONTEND_PID_FILE="$SCRIPT_ROOT/frontend.pid"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to add timestamp to each log line
add_timestamp() {
    while IFS= read -r line; do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line"
    done
}

# Function to check if a process is running
is_running() {
    local pid_file=$1
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0
        else
            rm -f "$pid_file"
            return 1
        fi
    fi
    return 1
}

# Function to start backend
start_backend() {
    print_status "Starting backend server..."
    if is_running "$BACKEND_PID_FILE"; then
        print_warning "Backend is already running (PID: $(cat $BACKEND_PID_FILE))"
        return 1
    fi
    
    cd "$BACKEND_PATH" && node server.js 2>&1 | add_timestamp > "$LOGS_DIR/backend.log" &
    local pid=$!
    echo $pid > "$BACKEND_PID_FILE"
    
    sleep 2
    if is_running "$BACKEND_PID_FILE"; then
        print_success "Backend started successfully (PID: $pid)"
        return 0
    else
        print_error "Failed to start backend"
        return 1
    fi
}

# Function to start frontend
start_frontend() {
    print_status "Starting frontend server..."
    if is_running "$FRONTEND_PID_FILE"; then
        print_warning "Frontend is already running (PID: $(cat $FRONTEND_PID_FILE))"
        return 1
    fi
    
    cd "$FRONTEND_PATH" && npm run dev 2>&1 | add_timestamp > "$LOGS_DIR/frontend.log" &
    local pid=$!
    echo $pid > "$FRONTEND_PID_FILE"
    
    sleep 3
    if is_running "$FRONTEND_PID_FILE"; then
        print_success "Frontend started successfully (PID: $pid)"
        return 0
    else
        print_error "Failed to start frontend"
        return 1
    fi
}

# Function to stop a service
stop_service() {
    local service_name=$1
    local pid_file=$2
    
    if is_running "$pid_file"; then
        local pid=$(cat "$pid_file")
        print_status "Stopping $service_name (PID: $pid)..."
        kill $pid
        sleep 2
        
        if ! is_running "$pid_file"; then
            print_success "$service_name stopped successfully"
            rm -f "$pid_file"
        else
            print_warning "Force killing $service_name..."
            kill -9 $pid
            rm -f "$pid_file"
            print_success "$service_name force stopped"
        fi
    else
        print_warning "$service_name is not running"
    fi
}

# Function to stop backend
stop_backend() {
    stop_service "Backend" "$BACKEND_PID_FILE"
}

# Function to stop frontend
stop_frontend() {
    stop_service "Frontend" "$FRONTEND_PID_FILE"
}

# Function to restart backend
restart_backend() {
    print_status "Restarting backend..."
    stop_backend
    sleep 1
    start_backend
}

# Function to restart frontend
restart_frontend() {
    print_status "Restarting frontend..."
    stop_frontend
    sleep 1
    start_frontend
}

# Function to show status
status() {
    echo -e "\n${BLUE}=== Openwalla Services Status ===${NC}"
    
    if is_running "$BACKEND_PID_FILE"; then
        echo -e "Backend:      ${GREEN}Running${NC} (PID: $(cat $BACKEND_PID_FILE))"
    else
        echo -e "Backend:      ${RED}Stopped${NC}"
    fi
    
    if is_running "$FRONTEND_PID_FILE"; then
        echo -e "Frontend:     ${GREEN}Running${NC} (PID: $(cat $FRONTEND_PID_FILE))"
    else
        echo -e "Frontend:     ${RED}Stopped${NC}"
    fi
    echo ""
}

# Function to start all services
start_all() {
    print_status "Starting all services..."
    start_backend
    sleep 2
    start_frontend
    status
}

# Function to stop all services
stop_all() {
    print_status "Stopping all services..."
    stop_frontend
    stop_backend
    print_success "All services stopped"
}

# Function to restart all services
restart_all() {
    print_status "Restarting all services..."
    stop_all
    sleep 2
    start_all
}

# Function to show logs
show_logs() {
    local service=$1
    case $service in
        "backend")
            if [ -f "$LOGS_DIR/backend.log" ]; then
                tail -f "$LOGS_DIR/backend.log"
            else
                print_error "Backend log file not found at $LOGS_DIR/backend.log"
            fi
            ;;
        "frontend")
            if [ -f "$LOGS_DIR/frontend.log" ]; then
                tail -f "$LOGS_DIR/frontend.log"
            else
                print_error "Frontend log file not found at $LOGS_DIR/frontend.log"
            fi
            ;;
        *)
            print_error "Unknown service. Use: backend or frontend"
            ;;
    esac
}

# Function to force kill processes on specified ports
force_kill_all() {
    local ports=(3000 8080)
    local found_process=false

    print_status "Checking for processes on ports ${ports[*]}..."

    for port in "${ports[@]}"; do
        local pids
        pids=$(lsof -i :"$port" -t 2>/dev/null)
        
        if [ -n "$pids" ]; then
            found_process=true
            print_status "Found processes on port $port (PIDs: $pids)"
            for pid in $pids; do
                local cmd=$(ps -p "$pid" -o comm= 2>/dev/null)
                print_status "Killing process $pid ($cmd) on port $port..."
                kill -9 "$pid" 2>/dev/null
                if [ $? -eq 0 ]; then
                    print_success "Process $pid on port $port killed successfully"
                else
                    print_error "Failed to kill process $pid on port $port"
                fi
            done
        else
            print_status "No processes found on port $port"
        fi
    done

    if [ "$found_process" = false ]; then
        print_success "No processes were found listening on ports ${ports[*]}"
    fi
}

# Function to install dependencies in backend and frontend
install() {
    print_status "Installing dependencies..."

    # Install backend dependencies
    if [ -d "$BACKEND_PATH" ]; then
        print_status "Running npm install in backend folder..."
        cd "$BACKEND_PATH" && npm install > "$LOGS_DIR/backend-install.log" 2>&1
        if [ $? -eq 0 ]; then
            print_success "Backend dependencies installed successfully"
        else
            print_error "Failed to install backend dependencies. Check $LOGS_DIR/backend-install.log for details"
            return 1
        fi
    else
        print_error "Backend directory not found: $BACKEND_PATH"
        return 1
    fi

    # Install frontend dependencies
    if [ -d "$FRONTEND_PATH" ]; then
        print_status "Running npm install in src folder..."
        cd "$FRONTEND_PATH" && npm install > "$LOGS_DIR/frontend-install.log" 2>&1
        if [ $? -eq 0 ]; then
            print_success "Frontend dependencies installed successfully"
        else
            print_error "Failed to install frontend dependencies. Check $LOGS_DIR/frontend-install.log for details"
            return 1
        fi
    else
        print_error "Frontend directory not found: $FRONTEND_PATH"
        return 1
    fi

    print_success "All dependencies installed successfully"
}

# Function to show help
show_help() {
    echo -e "\n${BLUE}Openwalla Server Management Script${NC}"
    echo -e "Usage: $0 [COMMAND] [SERVICE]\n"
    echo -e "Commands:"
    echo -e "  start [SERVICE]    Start service(s) (default: all)"
    echo -e "  stop [SERVICE]     Stop service(s)"
    echo -e "  restart [SERVICE]  Restart service(s)"
    echo -e "  status             Show status of all services"
    echo -e "  logs [SERVICE]     Show logs for a service"
    echo -e "  force_kill_all     Force kill processes on ports 3000, 8080"
    echo -e "  install            Install dependencies in backend and frontend"
    echo -e "  help               Show this help message"
    echo -e "\nServices:"
    echo -e "  backend      Backend server"
    echo -e "  frontend     Frontend server"
    echo -e "  all          All services"
    echo -e "\nExamples:"
    echo -e "  $0 start              # Start all services"
    echo -e "  $0 start backend      # Start only backend"
    echo -e "  $0 stop frontend      # Stop only frontend"
    echo -e "  $0 restart all        # Restart all services"
    echo -e "  $0 logs backend       # Show backend logs"
    echo -e "  $0 force_kill_all     # Kill processes on ports 3000, 8080"
    echo -e "  $0 install            # Install dependencies in backend and frontend"
    echo ""
}

# Main script logic
case $1 in
    "start")
        case $2 in
            "backend") start_backend ;;
            "frontend") start_frontend ;;
            "all"|"") start_all ;;
            *) print_error "Unknown service: $2"; show_help ;;
        esac
        ;;
    "stop")
        case $2 in
            "backend") stop_backend ;;
            "frontend") stop_frontend ;;
            "all"|"") stop_all ;;
            *) print_error "Unknown service: $2"; show_help ;;
        esac
        ;;
    "restart")
        case $2 in
            "backend") restart_backend ;;
            "frontend") restart_frontend ;;
            "all"|"") restart_all ;;
            *) print_error "Unknown service: $2"; show_help ;;
        esac
        ;;
    "status")
        status
        ;;
    "logs")
        show_logs $2
        ;;
    "force_kill_all")
        force_kill_all
        ;;
    "install")
        install
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    "")
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        show_help
        ;;
esac
