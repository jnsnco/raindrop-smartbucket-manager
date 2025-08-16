#!/bin/bash

# Raindrop SmartBucket Manager
# A comprehensive script to manage Raindrop smart buckets with menu-driven interface

set -e

# Color codes for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
API_BASE_URL="https://api.raindrop.run"
MANIFEST_FILE="raindrop.manifest"

# Global variables
BUCKET_NAME=""

# Utility functions
print_header() {
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}    Raindrop SmartBucket Manager${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo ""
}

print_section() {
    echo -e "${BLUE}--- $1 ---${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${PURPLE}ℹ $1${NC}"
}

# Format and display search results
display_search_results() {
    local response="$1"
    local description="$2"
    
    echo -e "${CYAN}$description:${NC}"
    
    # Check if response contains results
    if echo "$response" | jq -e '.results' >/dev/null 2>&1; then
        local results_count=$(echo "$response" | jq '.results | length')
        echo -e "${GREEN}Found $results_count result(s)${NC}"
        echo ""
        
        # Display each result
        echo "$response" | jq -r '.results[] | 
            "Result ID: " + (.chunkSignature // "N/A") + 
            "\nSource: " + (.source.objectKey // "N/A") + 
            "\nContent: " + (.content // "N/A") + 
            "\nScore: " + (.score // 0 | tostring) + 
            "\n" + ("-" * 50)'
        
        # Display pagination info if available
        if echo "$response" | jq -e '.hasMorePages' >/dev/null 2>&1; then
            local has_more=$(echo "$response" | jq -r '.hasMorePages')
            local current_page=$(echo "$response" | jq -r '.currentPage // 1')
            echo ""
            echo -e "${YELLOW}Pagination: Page $current_page${NC}"
            if [ "$has_more" = "true" ]; then
                echo -e "${YELLOW}More pages available - use option 7 to get next page${NC}"
            else
                echo -e "${GREEN}This is the last page${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}No results field found in response${NC}"
        # Fall back to raw JSON display
        if echo "$response" | jq empty 2>/dev/null; then
            echo "$response" | jq '.'
        else
            echo "$response"
        fi
    fi
    echo ""
}

# Pretty print curl command and response
execute_curl() {
    local curl_cmd="$1"
    local description="$2"
    
    echo -e "${YELLOW}Executing: $description${NC}"
    echo -e "${CYAN}Curl Command:${NC}"
    echo "$curl_cmd"
    echo ""
    
    echo -e "${CYAN}Response:${NC}"
    local response=$(eval "$curl_cmd" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        # Try to format as JSON, fallback to raw output
        if echo "$response" | jq empty 2>/dev/null; then
            echo "$response" | jq '.'
        else
            echo "$response"
        fi
        echo ""
        
        # Check if response contains error indicators
        if echo "$response" | grep -q "not_found\|error\|Error\|ERROR"; then
            print_error "API returned an error"
            return 1
        elif echo "$response" | grep -q "unauthorized\|Unauthorized\|UNAUTHORIZED"; then
            print_error "Authentication failed - check your API key"
            return 1
        else
            print_success "Request completed successfully"
        fi
    else
        print_error "Request failed with exit code: $exit_code"
        echo "$response"
    fi
    
    echo ""
    return $exit_code
}

# Execute curl and display search results in formatted way
execute_search_curl() {
    local curl_cmd="$1"
    local description="$2"
    
    echo -e "${YELLOW}Executing: $description${NC}"
    echo -e "${CYAN}Curl Command:${NC}"
    echo "$curl_cmd"
    echo ""
    
    local response=$(eval "$curl_cmd" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        # Check if response contains error indicators
        if echo "$response" | grep -q "not_found\|error\|Error\|ERROR"; then
            print_error "API returned an error"
            echo "$response" | jq '.' 2>/dev/null || echo "$response"
            return 1
        elif echo "$response" | grep -q "unauthorized\|Unauthorized\|UNAUTHORIZED"; then
            print_error "Authentication failed - check your API key"
            return 1
        else
            print_success "Request completed successfully"
            display_search_results "$response" "$description"
        fi
    else
        print_error "Request failed with exit code: $exit_code"
        echo "$response"
    fi
    
    echo ""
    return $exit_code
}

# Load configuration from environment and manifest
load_config() {
    # Parse manifest file to get first bucket name
    if [ -f "$MANIFEST_FILE" ]; then
        BUCKET_NAME=$(grep -o 'smartbucket "[^"]*"' "$MANIFEST_FILE" | head -n1 | sed 's/smartbucket "\([^"]*\)"/\1/')
    fi
}


# Setup function
setup_credentials() {
    print_section "Setup Credentials"
    
    print_info "Set the RAINDROP_API_KEY environment variable to configure your API key:"
    echo "  export RAINDROP_API_KEY=\"your_api_key_here\""
    echo ""
    
    if [ -n "${RAINDROP_API_KEY:-}" ]; then
        print_success "API key is set: ${RAINDROP_API_KEY:0:16}..."
    else
        print_warning "RAINDROP_API_KEY environment variable not set"
    fi
    
    echo ""
    print_info "Bucket configuration comes from raindrop.manifest file"
    if [ -n "$BUCKET_NAME" ]; then
        print_success "Found bucket in manifest: $BUCKET_NAME"
    else
        print_warning "No buckets found in manifest file"
        print_info "Run option 2 to create a manifest with a bucket"
    fi
}

# Create or edit raindrop.manifest
create_manifest() {
    print_section "Creating/Updating Raindrop Manifest"
    
    if [ -z "$BUCKET_NAME" ]; then
        echo -n "Enter bucket name: "
        read BUCKET_NAME
    fi
    
    # Check if manifest exists
    if [ -f "$MANIFEST_FILE" ]; then
        print_info "Manifest file exists. Checking for bucket definition..."
        
        if grep -q "smartbucket \"$BUCKET_NAME\"" "$MANIFEST_FILE"; then
            print_success "Bucket '$BUCKET_NAME' already defined in manifest"
        else
            print_info "Adding bucket '$BUCKET_NAME' to existing manifest"
            
            # Check if there's an application block
            if grep -q "application " "$MANIFEST_FILE"; then
                # Find the last closing brace and insert before it
                sed -i "/^}$/i\\    smartbucket \"$BUCKET_NAME\" {}" "$MANIFEST_FILE"
            else
                # No application block, need to wrap everything
                echo -n "Enter application name (default: my-app): "
                read app_name
                if [ -z "$app_name" ]; then
                    app_name="my-app"
                fi
                
                # Backup original content
                cp "$MANIFEST_FILE" "$MANIFEST_FILE.bak"
                
                # Create new manifest with application wrapper
                {
                    echo "// Raindrop Manifest"
                    echo "// Updated by SmartBucket Manager"
                    echo ""
                    echo "application \"$app_name\" {"
                    sed 's/^/    /' "$MANIFEST_FILE.bak"
                    echo "    smartbucket \"$BUCKET_NAME\" {}"
                    echo "}"
                } > "$MANIFEST_FILE"
                
                rm "$MANIFEST_FILE.bak"
            fi
            
            print_success "Added bucket to manifest"
        fi
    else
        print_info "Creating new manifest file"
        echo -n "Enter application name (default: my-app): "
        read app_name
        if [ -z "$app_name" ]; then
            app_name="my-app"
        fi
        
        cat > "$MANIFEST_FILE" << EOF
// Raindrop Manifest
// Auto-generated by SmartBucket Manager

application "$app_name" {
    smartbucket "$BUCKET_NAME" {}
}
EOF
        print_success "Created new manifest with application '$app_name' and bucket '$BUCKET_NAME'"
    fi
    
    # Reload configuration to pick up the new bucket
    load_config
}

# Build and generate smart bucket
build_smartbucket() {
    print_section "Building SmartBucket"
    
    if [ ! -f "$MANIFEST_FILE" ]; then
        print_error "No manifest file found. Creating one first..."
        create_manifest
    fi
    
    print_info "Running: raindrop build generate"
    
    if command -v raindrop >/dev/null 2>&1; then
        raindrop build generate
        print_success "SmartBucket generated successfully"
        
        # Show the current bucket name
        if [ -n "$BUCKET_NAME" ]; then
            print_info "Current bucket name: $BUCKET_NAME"
        fi
    else
        print_error "Raindrop CLI not found. Please install it first."
        print_info "You can install it from: https://docs.liquidmetal.ai/getting-started/"
        return 1
    fi
}

# Upload document
upload_document() {
    print_section "Upload Document"
    
    if [ -z "${RAINDROP_API_KEY:-}" ]; then
        print_error "API key not set. Please run setup first."
        return 1
    fi
    
    echo -n "Enter file path to upload: "
    read file_path
    
    if [ ! -f "$file_path" ]; then
        print_error "File not found: $file_path"
        return 1
    fi
    
    echo -n "Enter document key (or press Enter for filename): "
    read doc_key
    
    if [ -z "$doc_key" ]; then
        doc_key=$(basename "$file_path")
    fi
    
    # Use the bucket name directly
    if [ -z "$BUCKET_NAME" ]; then
        print_warning "No bucket configured. Please run setup first."
        echo -n "Enter bucket name: "
        read BUCKET_NAME
    fi
    
    print_info "Using bucket: $BUCKET_NAME"
    
    local curl_cmd="curl -s -X PUT \"$API_BASE_URL/v1/bucket/$BUCKET_NAME/$doc_key\" \
        -H \"Authorization: Bearer $RAINDROP_API_KEY\" \
        -H \"Content-Type: application/octet-stream\" \
        --data-binary \"@$file_path\""
    
    if ! execute_curl "$curl_cmd" "Upload document '$doc_key'"; then
        echo ""
        print_warning "If the bucket doesn't exist, run option 2 to create it first"
    fi
}

# List documents
list_documents() {
    print_section "List Documents"
    
    if [ -z "${RAINDROP_API_KEY:-}" ]; then
        print_error "API key not set. Please run setup first."
        return 1
    fi
    
    # Use the bucket name directly
    if [ -z "$BUCKET_NAME" ]; then
        print_warning "No bucket configured. Please run setup first."
        echo -n "Enter bucket name: "
        read BUCKET_NAME
    fi
    
    print_info "Using bucket: $BUCKET_NAME"
    
    # Prepare JSON payload for list_objects
    local json_payload=$(jq -n \
        --arg bucket "$BUCKET_NAME" \
        '{
            "bucket_location": {
                "bucket": {
                    "name": $bucket
                }
            }
        }')
    
    local curl_cmd="curl -s -X POST \"$API_BASE_URL/v1/list_objects\" \
        -H \"Authorization: Bearer $RAINDROP_API_KEY\" \
        -H \"Content-Type: application/json\" \
        -d '$json_payload'"
    
    if ! execute_curl "$curl_cmd" "List documents in bucket"; then
        echo ""
        print_warning "If the bucket doesn't exist, you may need to:"
        print_info "1. Run option 2 (Create/Update SmartBucket) to build and deploy the bucket"
        print_info "2. Make sure the bucket name '$BUCKET_NAME' is correct"
        print_info "3. Verify your API key has access to this bucket"
    fi
}

# Delete document
delete_document() {
    print_section "Delete Document"
    
    if [ -z "${RAINDROP_API_KEY:-}" ]; then
        print_error "API key not set. Please run setup first."
        return 1
    fi
    
    echo -n "Enter document key to delete: "
    read doc_key
    
    # Use the bucket name directly
    if [ -z "$BUCKET_NAME" ]; then
        print_warning "No bucket configured. Please run setup first."
        echo -n "Enter bucket name: "
        read BUCKET_NAME
    fi
    
    print_info "Using bucket: $BUCKET_NAME"
    
    local curl_cmd="curl -s -X DELETE \"$API_BASE_URL/v1/bucket/$BUCKET_NAME/$doc_key\" \
        -H \"Authorization: Bearer $RAINDROP_API_KEY\""
    
    execute_curl "$curl_cmd" "Delete document '$doc_key'"
}

# Semantic search
semantic_search() {
    print_section "Semantic Search"
    
    if [ -z "${RAINDROP_API_KEY:-}" ]; then
        print_error "API key not set. Please run setup first."
        return 1
    fi
    
    echo -n "Enter search query: "
    read search_query
    
    echo -n "Enter request ID (press Enter to generate new): "
    read request_id
    
    # Trim whitespace from request_id
    request_id=$(echo "$request_id" | xargs)
    
    # Generate UUID if no request_id provided
    if [ -z "$request_id" ]; then
        request_id=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "$(date +%s)-$$-$RANDOM")
        print_info "Generated request ID: $request_id"
    fi
    
    # Use the bucket name directly
    if [ -z "$BUCKET_NAME" ]; then
        print_warning "No bucket configured. Please run setup first."
        echo -n "Enter bucket name: "
        read BUCKET_NAME
    fi
    
    print_info "Using bucket: $BUCKET_NAME"
    
    # Prepare JSON payload
    local json_payload=$(jq -n \
        --arg input "$search_query" \
        --arg bucket "$BUCKET_NAME" \
        --arg req_id "$request_id" \
        '{
            input: $input,
            bucket_locations: [
                {
                    bucket: {
                        name: $bucket
                    }
                }
            ],
            request_id: $req_id
        }')
    
    local curl_cmd="curl -s -X POST \"$API_BASE_URL/v1/search\" \
        -H \"Authorization: Bearer $RAINDROP_API_KEY\" \
        -H \"Content-Type: application/json\" \
        -d '$json_payload'"
    
    if ! execute_curl "$curl_cmd" "Initiate semantic search"; then
        return 1
    fi
    
    # Step 2: Get the first page of results
    print_info "Getting first page of results..."
    local get_page_payload=$(jq -n \
        --arg req_id "$request_id" \
        '{
            request_id: $req_id,
            page: 1
        }')
    
    local get_page_cmd="curl -s -X POST \"$API_BASE_URL/v1/search_get_page\" \
        -H \"Authorization: Bearer $RAINDROP_API_KEY\" \
        -H \"Content-Type: application/json\" \
        -d '$get_page_payload'"
    
    execute_search_curl "$get_page_cmd" "Search Results (page 1)"
}

# Get additional search pages
get_search_page() {
    print_section "Get Search Page"
    
    if [ -z "${RAINDROP_API_KEY:-}" ]; then
        print_error "API key not set. Please run setup first."
        return 1
    fi
    
    echo -n "Enter request ID from previous search: "
    read request_id
    
    # Trim whitespace from request_id
    request_id=$(echo "$request_id" | xargs)
    
    if [ -z "$request_id" ]; then
        print_error "Request ID is required"
        return 1
    fi
    
    echo -n "Enter page number: "
    read page_num
    
    if [ -z "$page_num" ]; then
        page_num=1
    fi
    
    print_info "Getting page $page_num for request ID: $request_id"
    
    # Prepare JSON payload
    local json_payload=$(jq -n \
        --arg req_id "$request_id" \
        --argjson page "$page_num" \
        '{
            request_id: $req_id,
            page: $page
        }')
    
    local curl_cmd="curl -s -X POST \"$API_BASE_URL/v1/search_get_page\" \
        -H \"Authorization: Bearer $RAINDROP_API_KEY\" \
        -H \"Content-Type: application/json\" \
        -d '$json_payload'"
    
    execute_search_curl "$curl_cmd" "Search Results (page $page_num)"
}

# Document query (natural language)
document_query() {
    print_section "Natural Language Document Query"
    
    if [ -z "${RAINDROP_API_KEY:-}" ]; then
        print_error "API key not set. Please run setup first."
        return 1
    fi
    
    echo -n "Enter your question: "
    read query
    
    echo -n "Enter request ID (press Enter to generate new): "
    read request_id
    
    # Trim whitespace from request_id
    request_id=$(echo "$request_id" | xargs)
    
    # Generate UUID if no request_id provided
    if [ -z "$request_id" ]; then
        request_id=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "$(date +%s)-$$-$RANDOM")
        print_info "Generated request ID: $request_id"
    fi
    
    # Use the bucket name directly
    if [ -z "$BUCKET_NAME" ]; then
        print_warning "No bucket configured. Please run setup first."
        echo -n "Enter bucket name: "
        read BUCKET_NAME
    fi
    
    print_info "Using bucket: $BUCKET_NAME"
    
    # Prepare JSON payload
    local json_payload=$(jq -n \
        --arg input "$query" \
        --arg bucket "$BUCKET_NAME" \
        --arg req_id "$request_id" \
        '{
            input: $input,
            bucket_locations: [
                {
                    bucket: {
                        name: $bucket
                    }
                }
            ],
            request_id: $req_id
        }')
    
    local curl_cmd="curl -s -X POST \"$API_BASE_URL/v1/document_query\" \
        -H \"Authorization: Bearer $RAINDROP_API_KEY\" \
        -H \"Content-Type: application/json\" \
        -d '$json_payload'"
    
    execute_curl "$curl_cmd" "Document query"
}

# Summarize document/page
summarize_document() {
    print_section "Summarize Document/Page"
    
    if [ -z "${RAINDROP_API_KEY:-}" ]; then
        print_error "API key not set. Please run setup first."
        return 1
    fi
    
    echo -n "Enter document key: "
    read doc_key
    
    echo -n "Enter page number (optional, press Enter for entire document): "
    read page_num
    
    # Use the bucket name directly
    if [ -z "$BUCKET_NAME" ]; then
        print_warning "No bucket configured. Please run setup first."
        echo -n "Enter bucket name: "
        read BUCKET_NAME
    fi
    
    print_info "Using bucket: $BUCKET_NAME"
    
    # Create summarization query
    local summary_query="Summarize"
    if [ -n "$page_num" ]; then
        summary_query="Summarize page $page_num of"
    fi
    summary_query="$summary_query the document $doc_key"
    
    # Prepare JSON payload
    local json_payload=$(jq -n \
        --arg input "$summary_query" \
        --arg bucket "$BUCKET_NAME" \
        '{
            input: $input,
            bucket_locations: [
                {
                    bucket: {
                        name: $bucket
                    }
                }
            ]
        }')
    
    local curl_cmd="curl -s -X POST \"$API_BASE_URL/v1/document_query\" \
        -H \"Authorization: Bearer $RAINDROP_API_KEY\" \
        -H \"Content-Type: application/json\" \
        -d '$json_payload'"
    
    execute_curl "$curl_cmd" "Summarize document"
}

# Show current configuration
show_config() {
    print_section "Current Configuration"
    
    echo -e "${CYAN}Environment Variables:${NC}"
    if [ -n "${RAINDROP_API_KEY:-}" ]; then
        echo "  RAINDROP_API_KEY = ${RAINDROP_API_KEY:0:10}... (truncated)"
    else
        echo "  RAINDROP_API_KEY = NOT SET"
    fi
    
    echo ""
    echo -e "${CYAN}Script Variables:${NC}"
    echo "  BUCKET_NAME = $BUCKET_NAME (from manifest)"
    
    echo ""
    if [ -f "$MANIFEST_FILE" ]; then
        echo -e "${CYAN}Manifest file: $MANIFEST_FILE${NC}"
        cat "$MANIFEST_FILE"
    else
        print_warning "No manifest file found"
    fi
}

# Debug bucket resolution
debug_bucket() {
    print_section "Debug Bucket Resolution"
    
    echo -e "${CYAN}Step 1: Current script variables${NC}"
    echo "  BUCKET_NAME = '$BUCKET_NAME'"
    
    echo ""
    echo -e "${CYAN}Step 2: Bucket configuration${NC}"
    if [ -n "$BUCKET_NAME" ]; then
        echo "  Using bucket name directly: $BUCKET_NAME"
        echo -e "${GREEN}  ✓ Bucket name configured${NC}"
    else
        echo -e "${RED}  ✗ No bucket name configured${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Step 3: Environment variables${NC}"
    if [ -n "${RAINDROP_API_KEY:-}" ]; then
        echo "  RAINDROP_API_KEY: $RAINDROP_API_KEY"
    else
        echo "  RAINDROP_API_KEY: NOT SET"
    fi
    
    echo ""
    echo -e "${CYAN}Step 4: Manifest file check${NC}"
    if [ -f "$MANIFEST_FILE" ]; then
        echo "  Manifest file exists: $MANIFEST_FILE"
        echo "  Contents:"
        cat "$MANIFEST_FILE" | sed 's/^/    /'
    else
        echo "  No manifest file found"
    fi
}

# Main menu
show_menu() {
    echo ""
    echo -e "${YELLOW}Select an option:${NC}"
    echo "1. Setup credentials and configuration"
    echo "2. Create/Update SmartBucket (manifest + build)"
    echo "3. Upload document"
    echo "4. List documents"
    echo "5. Delete document"
    echo "6. Semantic search"
    echo "7. Get additional search pages"
    echo "8. Natural language document query"
    echo "9. Summarize document/page"
    echo "10. Show current configuration"
    echo "d. Debug bucket resolution"
    echo "0. Exit"
    echo ""
    echo -n "Enter your choice [0-10,d]: "
}

# Main execution
main() {
    print_header
    
    # Check for required tools
    if ! command -v jq >/dev/null 2>&1; then
        print_error "jq is required but not installed. Please install jq first."
        exit 1
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        print_error "curl is required but not installed. Please install curl first."
        exit 1
    fi
    
    # Load existing configuration
    load_config
    
    while true; do
        show_menu
        read choice
        
        case $choice in
            1)
                setup_credentials
                ;;
            2)
                echo -en "\nHaven't figured out how to do this via API yet, or if it's even possible. For now, you need to use an existing SmartBucket.
If you don't have one, refer to this tutorial, then ask ${YELLOW}Claude Code${NC} to build a simple SmartBucket app.
${BLUE}https://docs.liquidmetal.ai/tutorials/claude-code-mcp-setup/${NC}\n
Once that's done, copy the raindrop.manifest to the same directory as this script.\n" 
                # create_manifest
                # build_smartbucket
                ;;
            3)
                upload_document
                ;;
            4)
                list_documents
                ;;
            5)
                delete_document
                ;;
            6)
                semantic_search
                ;;
            7)
                get_search_page
                ;;
            8)
                document_query
                ;;
            9)
                summarize_document
                ;;
            10)
                show_config
                ;;
            d|D)
                debug_bucket
                ;;
            0)
                print_success "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please choose 0-10 or d."
                ;;
        esac
        
        echo ""
        echo -n "Press Enter to continue..."
        read
    done
}

# Run the main function
main "$@"
