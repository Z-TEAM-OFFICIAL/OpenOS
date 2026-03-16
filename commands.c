/* commands.c */
#include "commands.h"
#include <stdint.h>

/* External kernel functions */
extern void print(const char* str);
extern void put_char(char c);

/* Port I/O functions */
static inline void outb(uint16_t port, uint8_t val) {
    asm volatile ( "outb %0, %1" : : "a"(val), "Nd"(port) );
}

static inline uint8_t inb(uint16_t port) {
    uint8_t ret;
    asm volatile ( "inb %1, %0" : "=a"(ret) : "Nd"(port) );
    return ret;
}

/* Simple string comparison (case‑sensitive) */
int str_cmp(const char* s1, const char* s2) {
    while (*s1 && (*s1 == *s2)) { s1++; s2++; }
    return *(unsigned char*)s1 - *(unsigned char*)s2;
}

/* Case‑insensitive string comparison */
int str_icmp(const char* s1, const char* s2) {
    while (*s1 && *s2) {
        char c1 = *s1;
        char c2 = *s2;
        /* Convert to uppercase for comparison */
        if (c1 >= 'a' && c1 <= 'z') c1 -= 0x20;
        if (c2 >= 'a' && c2 <= 'z') c2 -= 0x20;
        if (c1 != c2) return c1 - c2;
        s1++; s2++;
    }
    /* If one string ended, check which one */
    char c1 = *s1;
    char c2 = *s2;
    if (c1 >= 'a' && c1 <= 'z') c1 -= 0x20;
    if (c2 >= 'a' && c2 <= 'z') c2 -= 0x20;
    return c1 - c2;
}

/* Check if string starts with a given prefix (case‑sensitive) */
int str_starts_with(const char* str, const char* prefix) {
    while (*prefix) {
        if (*str++ != *prefix++) return 0;
    }
    return 1;
}

/* Case‑insensitive version of str_starts_with */
int str_istarts_with(const char* str, const char* prefix) {
    while (*prefix) {
        char c1 = *str;
        char c2 = *prefix;
        if (c1 >= 'a' && c1 <= 'z') c1 -= 0x20;
        if (c2 >= 'a' && c2 <= 'z') c2 -= 0x20;
        if (c1 != c2) return 0;
        str++; prefix++;
    }
    return 1;
}

/* Convert a string to integer (simple, no error checking) */
int str_to_int(const char* str) {
    int result = 0;
    while (*str >= '0' && *str <= '9') {
        result = result * 10 + (*str++ - '0');
    }
    return result;
}

/* Skip leading spaces */
const char* skip_spaces(const char* str) {
    while (*str == ' ') str++;
    return str;
}

/* Read a byte from CMOS RAM */
static uint8_t cmos_read(uint8_t reg) {
    outb(0x70, reg);
    return inb(0x71);
}

/* BEEP command */
void cmd_beep() {
    uint8_t temp = (uint8_t)0x42;
    outb(0x61, temp | 3);
    for(int i = 0; i < 1000000; i++);
    outb(0x61, temp & 0xFC);
    print("BEEP!\n");
}

/* ----- Existing commands (unchanged) ----- */

void cmd_mem() {
    uint16_t base_mem_kb = cmos_read(0x15) | (cmos_read(0x16) << 8);
    uint16_t ext_mem_kb  = cmos_read(0x30) | (cmos_read(0x31) << 8);
    uint32_t total_kb = base_mem_kb + ext_mem_kb;
    
    uint16_t high_mem_blocks = cmos_read(0x34) | (cmos_read(0x35) << 8);
    if (high_mem_blocks) {
        total_kb += high_mem_blocks * 64;
    }
    
    print("Total RAM: ");
    
    if (total_kb >= 1024*1024) {
        uint32_t gb = total_kb / (1024*1024);
        uint32_t mb_remain = (total_kb % (1024*1024)) / 1024;
        char buf[32];
        int i = 0;
        if (gb >= 10) buf[i++] = '0' + (gb/10);
        buf[i++] = '0' + (gb%10);
        buf[i++] = '.';
        buf[i++] = '0' + (mb_remain/100);
        buf[i++] = '0' + ((mb_remain/10)%10);
        buf[i++] = '0' + (mb_remain%10);
        buf[i++] = ' ';
        buf[i++] = 'G';
        buf[i++] = 'B';
        buf[i++] = '\n';
        buf[i++] = '\0';
        print(buf);
    } else {
        uint32_t mb = total_kb / 1024;
        uint32_t kb_remain = total_kb % 1024;
        char buf[32];
        int i = 0;
        if (mb >= 100) buf[i++] = '0' + (mb/100);
        if (mb >= 10) buf[i++] = '0' + ((mb/10)%10);
        buf[i++] = '0' + (mb%10);
        buf[i++] = '.';
        buf[i++] = '0' + (kb_remain/100);
        buf[i++] = '0' + ((kb_remain/10)%10);
        buf[i++] = '0' + (kb_remain%10);
        buf[i++] = ' ';
        buf[i++] = 'M';
        buf[i++] = 'B';
        buf[i++] = '\n';
        buf[i++] = '\0';
        print(buf);
    }
    
    print("(32-bit OS can address up to 4GB)\n");
}

void cmd_date() {
    uint8_t day   = cmos_read(0x07);
    uint8_t month = cmos_read(0x08);
    uint8_t year  = cmos_read(0x09);
    uint8_t century = cmos_read(0x32);
    
    day   = (day & 0x0F) + ((day >> 4) * 10);
    month = (month & 0x0F) + ((month >> 4) * 10);
    year  = (year & 0x0F) + ((year >> 4) * 10);
    if (century) {
        century = (century & 0x0F) + ((century >> 4) * 10);
    } else {
        century = 20;
    }
    
    char buf[32];
    int i = 0;
    buf[i++] = '0' + (day/10);
    buf[i++] = '0' + (day%10);
    buf[i++] = '/';
    buf[i++] = '0' + (month/10);
    buf[i++] = '0' + (month%10);
    buf[i++] = '/';
    buf[i++] = '0' + (century/10);
    buf[i++] = '0' + (century%10);
    buf[i++] = '0' + (year/10);
    buf[i++] = '0' + (year%10);
    buf[i++] = '\n';
    buf[i++] = '\0';
    print(buf);
}

void cmd_rtc() {
    uint8_t hour   = cmos_read(0x04);
    uint8_t minute = cmos_read(0x02);
    uint8_t second = cmos_read(0x00);
    
    hour   = (hour & 0x0F) + ((hour >> 4) * 10);
    minute = (minute & 0x0F) + ((minute >> 4) * 10);
    second = (second & 0x0F) + ((second >> 4) * 10);
    
    char buf[32];
    int i = 0;
    buf[i++] = '0' + (hour/10);
    buf[i++] = '0' + (hour%10);
    buf[i++] = ':';
    buf[i++] = '0' + (minute/10);
    buf[i++] = '0' + (minute%10);
    buf[i++] = ':';
    buf[i++] = '0' + (second/10);
    buf[i++] = '0' + (second%10);
    buf[i++] = '\n';
    buf[i++] = '\0';
    print(buf);
}

void cmd_cpu() {
    uint32_t eax, ebx, ecx, edx;
    
    asm volatile (
        "xorl %%eax, %%eax\n"
        "cpuid\n"
        : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx)
        :
        : /* no clobbers */
    );
    
    if (eax == 0) {
        print("CPUID not supported?\n");
        return;
    }
    
    char vendor[13];
    *((uint32_t*)vendor) = ebx;
    *((uint32_t*)(vendor+4)) = edx;
    *((uint32_t*)(vendor+8)) = ecx;
    vendor[12] = '\0';
    
    print("CPU Vendor: ");
    print(vendor);
    print("\n");
    
    asm volatile (
        "movl $1, %%eax\n"
        "cpuid\n"
        : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx)
        :
        : /* no clobbers */
    );
    
    uint8_t family = (eax >> 8) & 0xF;
    uint8_t model  = (eax >> 4) & 0xF;
    uint8_t stepping = eax & 0xF;
    
    char buf[64];
    int i = 0;
    buf[i++] = 'F';
    buf[i++] = 'a';
    buf[i++] = 'm';
    buf[i++] = 'i';
    buf[i++] = 'l';
    buf[i++] = 'y';
    buf[i++] = ':';
    buf[i++] = ' ';
    buf[i++] = '0' + (family/10);
    buf[i++] = '0' + (family%10);
    buf[i++] = ' ';
    buf[i++] = 'M';
    buf[i++] = 'o';
    buf[i++] = 'd';
    buf[i++] = 'e';
    buf[i++] = 'l';
    buf[i++] = ':';
    buf[i++] = ' ';
    buf[i++] = '0' + (model/10);
    buf[i++] = '0' + (model%10);
    buf[i++] = ' ';
    buf[i++] = 'S';
    buf[i++] = 't';
    buf[i++] = 'e';
    buf[i++] = 'p';
    buf[i++] = 'p';
    buf[i++] = 'i';
    buf[i++] = 'n';
    buf[i++] = 'g';
    buf[i++] = ':';
    buf[i++] = ' ';
    buf[i++] = '0' + (stepping/10);
    buf[i++] = '0' + (stepping%10);
    buf[i++] = '\n';
    buf[i++] = '\0';
    print(buf);
    
    if (edx & (1 << 4)) print("  RDTSC supported\n");
    if (edx & (1 << 15)) print("  CMOV supported\n");
    if (edx & (1 << 23)) print("  MMX supported\n");
    if (edx & (1 << 25)) print("  SSE supported\n");
    if (edx & (1 << 26)) print("  SSE2 supported\n");
}

void cmd_sysinfo() {
    print("OpenOS v0.1 - Jim Build\n");
    print("32-bit Protected Mode\n");
    cmd_cpu();
    cmd_mem();
}

void cmd_echo(const char* args) {
    args = skip_spaces(args);
    if (*args == '\0') {
        print("\n");
    } else {
        print(args);
        print("\n");
    }
}

void cmd_color(const char* args) {
    args = skip_spaces(args);
    int fg = str_to_int(args);
    while (*args && *args != ' ') args++;
    args = skip_spaces(args);
    int bg = str_to_int(args);
    
    if (fg < 30) fg = 37;
    if (fg > 37) fg = 37;
    if (bg < 40) bg = 40;
    if (bg > 47) bg = 40;
    
    char buf[16];
    int i = 0;
    buf[i++] = 0x1B;
    buf[i++] = '[';
    buf[i++] = '0' + (fg/10);
    buf[i++] = '0' + (fg%10);
    buf[i++] = ';';
    buf[i++] = '0' + (bg/10);
    buf[i++] = '0' + (bg%10);
    buf[i++] = 'm';
    buf[i++] = '\0';
    print(buf);
}

void cmd_calc(const char* args) {
    args = skip_spaces(args);
    int a = str_to_int(args);
    while (*args && *args != ' ') args++;
    args = skip_spaces(args);
    int b = str_to_int(args);
    
    int result = a + b;
    
    char buf[32];
    int i = 0;
    if (result < 0) {
        buf[i++] = '-';
        result = -result;
    }
    char digits[16];
    int j = 0;
    do {
        digits[j++] = '0' + (result % 10);
        result /= 10;
    } while (result > 0);
    while (j > 0) {
        buf[i++] = digits[--j];
    }
    buf[i++] = '\n';
    buf[i++] = '\0';
    print(buf);
}

void cmd_clear() {
    print("\033[2J\033[H");
}

void cmd_halt() {
    print("Halting System.\n");
    asm volatile ("hlt");
}

void cmd_reset() {
    print("Rebooting...\n");
    outb(0x64, 0xFE);
}

void cmd_about() {
    print("OpenOS v0.1 - Jim Build\n");
    print("A simple 32-bit protected mode OS\n");
    print("Written for learning purposes\n");
    print("Commands: type HELP for list\n");
}

/* ----- New commands: CD and LS (no simulated directories) ----- */

/* Simple current directory string (just for show) */
static const char* current_dir = "/";  /* root directory */

void cmd_cd(const char* args) {
    args = skip_spaces(args);
    if (*args == '\0') {
        /* No argument: just print current directory */
        print("Current directory: ");
        print(current_dir);
        print("\n");
    } else {
        /* Ignore the argument – no real filesystem */
        print("CD: Directory change not implemented (no filesystem)\n");
        /* Optionally update current_dir for show? But they said no simulation */
        /* We'll leave it unchanged */
    }
}

void cmd_ls() {
    print("LS: No filesystem – cannot list directories\n");
    /* Could print a dummy message, but they asked for no simulated dirs */
}

/* ----- Main command dispatcher (case‑insensitive) ----- */
void handle_command(const char* cmd) {
    /* Check for exact-match commands using case‑insensitive compare */
    if (str_icmp(cmd, "VER") == 0) {
        print("OpenOS v0.1 - Jim Build\n");
    }
    else if (str_icmp(cmd, "HELP") == 0) {
        print("Available commands:\n");
        print("  VER    - Show version\n");
        print("  HELP   - This help\n");
        print("  CLS    - Clear screen\n");
        print("  BEEP   - PC speaker beep\n");
        print("  INFO   - System info (basic)\n");
        print("  REBOOT - Reboot system\n");
        print("  TIME   - Placeholder time\n");
        print("  EXIT   - Halt system\n");
        print("  MEM    - Show memory size\n");
        print("  DATE   - Show current date\n");
        print("  RTC    - Show current time\n");
        print("  CPU    - CPU details\n");
        print("  SYSINFO- Full system info\n");
        print("  ECHO   - Echo arguments\n");
        print("  COLOR  - Set text color (fg bg)\n");
        print("  CALC   - Add two numbers\n");
        print("  CLEAR  - Alias for CLS\n");
        print("  HALT   - Halt system\n");
        print("  RESET  - Reboot system\n");
        print("  ABOUT  - About this OS\n");
        print("  CD     - Show/change directory (no filesystem)\n");
        print("  LS     - List directory (not implemented)\n");
    }
    else if (str_icmp(cmd, "CLS") == 0) {
        print("\033[2J\033[H");
    }
    else if (str_icmp(cmd, "BEEP") == 0) {
        cmd_beep();
    }
    else if (str_icmp(cmd, "INFO") == 0) {
        print("CPU: x86 Compatible\nMode: 32-bit Protected\n");
    }
    else if (str_icmp(cmd, "REBOOT") == 0) {
        print("Rebooting...\n");
        outb(0x64, 0xFE);
    }
    else if (str_icmp(cmd, "TIME") == 0) {
        print("RTC Clock: Use CMOS read to implement.\n");
    }
    else if (str_icmp(cmd, "EXIT") == 0) {
        print("Halting System.\n");
        asm volatile ("hlt");
    }
    /* Commands that may have arguments (use case‑insensitive prefix) */
    else if (str_istarts_with(cmd, "MEM")) {
        cmd_mem();
    }
    else if (str_istarts_with(cmd, "DATE")) {
        cmd_date();
    }
    else if (str_istarts_with(cmd, "RTC")) {
        cmd_rtc();
    }
    else if (str_istarts_with(cmd, "CPU")) {
        cmd_cpu();
    }
    else if (str_istarts_with(cmd, "SYSINFO")) {
        cmd_sysinfo();
    }
    else if (str_istarts_with(cmd, "ECHO")) {
        cmd_echo(cmd + 4);  /* skip "ECHO" */
    }
    else if (str_istarts_with(cmd, "COLOR")) {
        cmd_color(cmd + 5); /* skip "COLOR" */
    }
    else if (str_istarts_with(cmd, "CALC")) {
        cmd_calc(cmd + 4);  /* skip "CALC" */
    }
    else if (str_istarts_with(cmd, "CLEAR")) {
        cmd_clear();
    }
    else if (str_istarts_with(cmd, "HALT")) {
        cmd_halt();
    }
    else if (str_istarts_with(cmd, "RESET")) {
        cmd_reset();
    }
    else if (str_istarts_with(cmd, "ABOUT")) {
        cmd_about();
    }
    /* New CD and LS commands */
    else if (str_istarts_with(cmd, "CD")) {
        cmd_cd(cmd + 2);  /* pass the argument part */
    }
    else if (str_istarts_with(cmd, "LS")) {
        cmd_ls();
    }
    else {
        print("Bad command.\n");
    }
}