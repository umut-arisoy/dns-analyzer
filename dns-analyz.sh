#!/bin/bash

# BDDK Banka DNS Analiz Tool - Bash Version
# Bu script BDDK bankalarının DNS servislerini tespit eder ve rapor oluşturur.

# Renkli output için ANSI kodları
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Varsayılan değerler
DOMAINS_FILE="bddk_banks_domains.txt"
OUTPUT_DIR="dns_reports"
MAX_JOBS=10
QUIET=false
TIMEOUT=10

# Banner fonksiyonu
show_banner() {
    if [ "$QUIET" = false ]; then
        echo -e "${CYAN}"
        echo "╔═══════════════════════════════════════════════════════╗"
        echo "║              BDDK BANKA DNS ANALİZ TOOL               ║"
        echo "║                    BASH VERSION                       ║"
        echo "║                                                       ║"
        echo "║  🏦 BDDK bankalarının DNS servislerini tespit eder    ║"
        echo "║  📊 Detaylı raporlar oluşturur                        ║"
        echo "║  🚀 Paralel işlem desteği                             ║"
        echo "╚═══════════════════════════════════════════════════════╝"
        echo -e "${NC}"
    fi
}

# Yardım mesajı
show_help() {
    echo "Kullanım: $0 [SEÇENEKLER]"
    echo ""
    echo "Seçenekler:"
    echo "  -d, --domains FILE     Domain listesi dosyası (varsayılan: bddk_banks_domains.txt)"
    echo "  -o, --output DIR       Çıktı dizini (varsayılan: dns_reports)"
    echo "  -j, --jobs NUMBER      Maksimum paralel işlem sayısı (varsayılan: 10)"
    echo "  -t, --timeout SECONDS  DNS sorgusu zaman aşımı (varsayılan: 10)"
    echo "  -q, --quiet            Sessiz mod"
    echo "  -h, --help             Bu yardım mesajını göster"
    echo ""
    echo "Örnekler:"
    echo "  $0                                    # Varsayılan ayarlarla çalıştır"
    echo "  $0 -d domains.txt -o reports         # Özel dosya ve dizin"
    echo "  $0 -j 20 -t 5                       # 20 paralel işlem, 5sn timeout"
    echo "  $0 -q                               # Sessiz mod"
}

# DNS sağlayıcısı tespit fonksiyonu
identify_dns_provider() {
    local ns_servers="$1"
    local provider="Bilinmeyen DNS Sağlayıcısı"
    
    # NS sunucu isimlerine göre tespit
    if echo "$ns_servers" | grep -qi "cloudflare"; then
        provider="Cloudflare"
    elif echo "$ns_servers" | grep -qi "google"; then
        provider="Google DNS"
    elif echo "$ns_servers" | grep -qi "amazonaws\|aws"; then
        provider="AWS Route53"
    elif echo "$ns_servers" | grep -qi "azure\|microsoft"; then
        provider="Microsoft Azure DNS"
    elif echo "$ns_servers" | grep -qi "godaddy"; then
        provider="GoDaddy"
    elif echo "$ns_servers" | grep -qi "namecheap"; then
        provider="Namecheap"
    elif echo "$ns_servers" | grep -qi "dnsmadeeasy"; then
        provider="DNS Made Easy"
    elif echo "$ns_servers" | grep -qi "dnsimple"; then
        provider="DNSimple"
    elif echo "$ns_servers" | grep -qi "he\.net"; then
        provider="Hurricane Electric"
    elif echo "$ns_servers" | grep -qi "digiturk\|ttnet"; then
        provider="Türk Telekom"
    elif echo "$ns_servers" | grep -qi "superonline"; then
        provider="Superonline"
    elif echo "$ns_servers" | grep -qi "turkcell"; then
        provider="Turkcell"
    elif echo "$ns_servers" | grep -qi "vodafone"; then
        provider="Vodafone"
    elif echo "$ns_servers" | grep -qi "\.tr$"; then
        provider="Türkiye Yerel DNS"
    elif echo "$ns_servers" | grep -qi "\.com$"; then
        provider="Uluslararası DNS Sağlayıcısı"
    fi
    
    echo "$provider"
}

# Tek domain analiz fonksiyonu
analyze_domain() {
    local domain="$1"
    local temp_file="$2"
    local start_time=$(date +%s.%N)
    
    if [ "$QUIET" = false ]; then
        echo -e "${BLUE}🔍 Analiz ediliyor: ${domain}${NC}"
    fi
    
    # NS kayıtlarını al
    local ns_query
    ns_query=$(dig +short +timeout=$TIMEOUT NS "$domain" 2>/dev/null)
    local dig_exit_code=$?
    
    local status="success"
    local error=""
    local ns_servers=""
    local dns_provider=""
    local ip_addresses=""
    
    if [ $dig_exit_code -ne 0 ] || [ -z "$ns_query" ]; then
        status="error"
        error="NS kayıtları alınamadı"
        dns_provider="Tespit Edilemedi"
    else
        # NS sunucularını temizle (nokta kaldır)
        ns_servers=$(echo "$ns_query" | sed 's/\.$//' | tr '\n' ',' | sed 's/,$//')
        
        # DNS sağlayıcısını tespit et
        dns_provider=$(identify_dns_provider "$ns_servers")
        
        # NS sunucularının IP adreslerini al
        local ips=""
        while IFS= read -r ns; do
            if [ -n "$ns" ]; then
                local ns_clean=$(echo "$ns" | sed 's/\.$//')
                local ip_a=$(dig +short +timeout=$TIMEOUT A "$ns_clean" 2>/dev/null | head -3)
                local ip_aaaa=$(dig +short +timeout=$TIMEOUT AAAA "$ns_clean" 2>/dev/null | head -1)
                
                if [ -n "$ip_a" ]; then
                    ips="$ips,$ip_a"
                fi
                if [ -n "$ip_aaaa" ]; then
                    ips="$ips,$ip_aaaa"
                fi
            fi
        done <<< "$ns_query"
        
        ip_addresses=$(echo "$ips" | sed 's/^,//' | tr '\n' ',' | sed 's/,$//')
    fi
    
    local end_time=$(date +%s.%N)
    local response_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0.000")
    local timestamp=$(date --iso-8601=seconds)
    
    # Sonucu temp dosyaya yaz (CSV formatında)
    {
        echo "$domain,$dns_provider,$status,${response_time:0:5},$ns_servers,$ip_addresses,$error,$timestamp"
    } >> "$temp_file"
    
    # Ekran çıktısı
    if [ "$QUIET" = false ]; then
        case "$status" in
            "success")
                echo -e "${GREEN}✅ ${domain} - ${dns_provider} (${response_time:0:4}s)${NC}"
                ;;
            "error")
                echo -e "${RED}❌ ${domain} - ${error} (${response_time:0:4}s)${NC}"
                ;;
            *)
                echo -e "${YELLOW}⚠️  ${domain} - ${dns_provider} (${response_time:0:4}s)${NC}"
                ;;
        esac
    fi
}

# TXT rapor oluştur
generate_txt_report() {
    local csv_file="$1"
    local output_file="$2"
    local timestamp=$(date '+%d.%m.%Y %H:%M:%S')
    local total_domains=$(wc -l < "$csv_file")
    
    {
        echo "BDDK BANKA DNS ANALİZ RAPORU"
        echo "=================================================="
        echo "Rapor Tarihi: $timestamp"
        echo "Toplam Domain: $total_domains"
        echo ""
        printf "%-35s %-30s %-10s\n" "DOMAIN" "DNS SAĞLAYICISI" "DURUM"
        echo "--------------------------------------------------------------------------------"
        
        # CSV dosyasını oku ve formatla
        while IFS=',' read -r domain provider status response_time ns_servers ip_addresses error timestamp; do
            printf "%-35s %-30s %-10s\n" "$domain" "${provider:0:29}" "$status"
        done < <(sort "$csv_file")
    } > "$output_file"
}

# Detaylı TXT rapor oluştur
generate_detailed_report() {
    local csv_file="$1"
    local output_file="$2"
    local timestamp=$(date '+%d.%m.%Y %H:%M:%S')
    local total_domains=$(wc -l < "$csv_file")
    
    {
        echo "BDDK BANKA DETAYLI DNS ANALİZ RAPORU"
        echo "============================================================"
        echo "Rapor Tarihi: $timestamp"
        echo "Toplam Domain: $total_domains"
        echo ""
        
        # DNS sağlayıcı istatistikleri
        echo "DNS SAĞLAYICI İSTATİSTİKLERİ:"
        echo "----------------------------------------"
        
        # Sağlayıcıları say ve sırala
        cut -d',' -f2 "$csv_file" | sort | uniq -c | sort -nr | while read count provider; do
            echo "$provider: $count domain"
        done
        
        echo ""
        echo "DETAYLI DOMAIN BİLGİLERİ:"
        echo "----------------------------------------"
        echo ""
        
        # Detaylı bilgiler
        while IFS=',' read -r domain provider status response_time ns_servers ip_addresses error timestamp; do
            echo "Domain: $domain"
            echo "DNS Sağlayıcısı: $provider"
            echo "Durum: $status"
            echo "Yanıt Süresi: ${response_time}s"
            echo "NS Sunucuları: ${ns_servers:-Yok}"
            echo "IP Adresleri: ${ip_addresses:-Yok}"
            
            if [ -n "$error" ] && [ "$error" != "" ]; then
                echo "Hata: $error"
            fi
            
            echo ""
            echo "----------------------------------------"
            echo ""
        done < <(sort "$csv_file")
    } > "$output_file"
}

# CSV rapor header ekle
generate_csv_report() {
    local temp_csv="$1"
    local output_csv="$2"
    
    {
        echo "Domain,DNS Sağlayıcısı,Durum,Yanıt Süresi (s),NS Sunucuları,IP Adresleri,Hata,Zaman"
        sort "$temp_csv"
    } > "$output_csv"
}

# JSON rapor oluştur (basit)
generate_json_report() {
    local csv_file="$1"
    local output_file="$2"
    local timestamp=$(date --iso-8601=seconds)
    local total_domains=$(wc -l < "$csv_file")
    
    {
        echo "{"
        echo "  \"metadata\": {"
        echo "    \"generated_at\": \"$timestamp\","
        echo "    \"total_domains\": $total_domains,"
        echo "    \"tool_version\": \"bash-1.0\""
        echo "  },"
        echo "  \"results\": ["
        
        local first=true
        while IFS=',' read -r domain provider status response_time ns_servers ip_addresses error timestamp; do
            if [ "$first" = true ]; then
                first=false
            else
                echo ","
            fi
            
            echo -n "    {"
            echo -n "\"domain\":\"$domain\","
            echo -n "\"dns_provider\":\"$provider\","
            echo -n "\"status\":\"$status\","
            echo -n "\"response_time\":$response_time,"
            echo -n "\"ns_servers\":\"$ns_servers\","
            echo -n "\"ip_addresses\":\"$ip_addresses\","
            echo -n "\"error\":\"$error\","
            echo -n "\"timestamp\":\"$timestamp\""
            echo -n "}"
        done < <(sort "$csv_file")
        
        echo ""
        echo "  ]"
        echo "}"
    } > "$output_file"
}

# Ana fonksiyon
main() {
    # Komut satırı argümanlarını parse et
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--domains)
                DOMAINS_FILE="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -j|--jobs)
                MAX_JOBS="$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Bilinmeyen seçenek: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Banner göster
    show_banner
    
    # Gerekli komutları kontrol et
    for cmd in dig bc; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}❌ $cmd komutu bulunamadı! Lütfen yükleyin.${NC}"
            exit 1
        fi
    done
    
    # Domain dosyasını kontrol et
    if [ ! -f "$DOMAINS_FILE" ]; then
        echo -e "${RED}❌ Domain dosyası bulunamadı: $DOMAINS_FILE${NC}"
        exit 1
    fi
    
    # Çıktı dizinini oluştur
    mkdir -p "$OUTPUT_DIR"
    
    # Domain sayısını al
    local total_domains=$(wc -l < "$DOMAINS_FILE")
    
    if [ "$QUIET" = false ]; then
        echo -e "${WHITE}📂 Domain dosyası: $DOMAINS_FILE${NC}"
        echo -e "${WHITE}📊 Toplam domain: $total_domains${NC}"
        echo -e "${WHITE}🚀 Maksimum paralel işlem: $MAX_JOBS${NC}"
        echo -e "${WHITE}⏱️  DNS timeout: ${TIMEOUT}s${NC}"
        echo -e "${WHITE}📁 Çıktı dizini: $OUTPUT_DIR${NC}"
        echo ""
        echo -e "${CYAN}🔍 Analiz başlıyor...${NC}"
        echo "------------------------------------------------------------"
    fi
    
    # Geçici dosya oluştur
    local temp_csv=$(mktemp)
    local start_time=$(date +%s)
    
    # Domainleri paralel olarak analiz et
    export -f analyze_domain identify_dns_provider
    export TIMEOUT QUIET RED GREEN YELLOW BLUE NC
    
    # GNU parallel kullan (varsa), yoksa xargs kullan
    if command -v parallel &> /dev/null; then
        cat "$DOMAINS_FILE" | parallel -j "$MAX_JOBS" analyze_domain {} "$temp_csv"
    else
        cat "$DOMAINS_FILE" | xargs -n 1 -P "$MAX_JOBS" -I {} bash -c "analyze_domain '{}' '$temp_csv'"
    fi
    
    local end_time=$(date +%s)
    local elapsed_time=$((end_time - start_time))
    
    if [ "$QUIET" = false ]; then
        echo "------------------------------------------------------------"
        echo -e "${GREEN}⏱️  Analiz tamamlandı! Toplam süre: ${elapsed_time} saniye${NC}"
        echo -e "${CYAN}📊 Raporlar oluşturuluyor...${NC}"
    fi
    
    # Zaman damgası
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    
    # Raporları oluştur
    local txt_file="$OUTPUT_DIR/bddk_dns_report_$timestamp.txt"
    local detailed_txt_file="$OUTPUT_DIR/bddk_dns_detailed_$timestamp.txt"
    local csv_file="$OUTPUT_DIR/bddk_dns_report_$timestamp.csv"
    local json_file="$OUTPUT_DIR/bddk_dns_report_$timestamp.json"
    
    generate_txt_report "$temp_csv" "$txt_file"
    generate_detailed_report "$temp_csv" "$detailed_txt_file"
    generate_csv_report "$temp_csv" "$csv_file"
    generate_json_report "$temp_csv" "$json_file"
    
    # Geçici dosyayı sil
    rm "$temp_csv"
    
    if [ "$QUIET" = false ]; then
        echo -e "${GREEN}📄 Basit rapor kaydedildi: $txt_file${NC}"
        echo -e "${GREEN}📄 Detaylı rapor kaydedildi: $detailed_txt_file${NC}"
        echo -e "${GREEN}📊 CSV rapor kaydedildi: $csv_file${NC}"
        echo -e "${GREEN}🔧 JSON rapor kaydedildi: $json_file${NC}"
        
        # Özet istatistikler
        local success_count=$(grep -c ",success," "$csv_file" 2>/dev/null || echo "0")
        local error_count=$(grep -c ",error," "$csv_file" 2>/dev/null || echo "0")
        
        echo ""
        echo -e "${WHITE}📈 ÖZET İSTATİSTİKLER:${NC}"
        echo -e "   ${GREEN}✅ Başarılı: $success_count${NC}"
        echo -e "   ${RED}❌ Hatalı: $error_count${NC}"
        echo -e "   ${BLUE}📁 Çıktı dizini: $OUTPUT_DIR${NC}"
        
        # En çok kullanılan DNS sağlayıcıları
        echo ""
        echo -e "${WHITE}🥇 EN ÇOK KULLANILAN DNS SAĞLAYICILARI:${NC}"
        cut -d',' -f2 "$csv_file" | tail -n +2 | sort | uniq -c | sort -nr | head -5 | while read count provider; do
            echo -e "   ${PURPLE}$provider: $count domain${NC}"
        done
        
        echo ""
        echo -e "${GREEN}🎉 Analiz tamamlandı! Raporlar $OUTPUT_DIR dizininde.${NC}"
    fi
}

# Scripti çalıştır
main "$@"
