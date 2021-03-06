-- #################################################################################################
-- # << NEORV32 - Default Testbench >>                                                             #
-- # ********************************************************************************************* #
-- # The processor is configured to use a maximum of functional units (for testing purpose).       #
-- # Use the "User Configuration" section to configure the testbench according to your needs.      #
-- # See NEORV32 data sheet (docs/NEORV32.pdf) for more information.                               #
-- # ********************************************************************************************* #
-- # BSD 3-Clause License                                                                          #
-- #                                                                                               #
-- # Copyright (c) 2021, Stephan Nolting. All rights reserved.                                     #
-- #                                                                                               #
-- # Redistribution and use in source and binary forms, with or without modification, are          #
-- # permitted provided that the following conditions are met:                                     #
-- #                                                                                               #
-- # 1. Redistributions of source code must retain the above copyright notice, this list of        #
-- #    conditions and the following disclaimer.                                                   #
-- #                                                                                               #
-- # 2. Redistributions in binary form must reproduce the above copyright notice, this list of     #
-- #    conditions and the following disclaimer in the documentation and/or other materials        #
-- #    provided with the distribution.                                                            #
-- #                                                                                               #
-- # 3. Neither the name of the copyright holder nor the names of its contributors may be used to  #
-- #    endorse or promote products derived from this software without specific prior written      #
-- #    permission.                                                                                #
-- #                                                                                               #
-- # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS   #
-- # OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF               #
-- # MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE    #
-- # COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,     #
-- # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE #
-- # GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED    #
-- # AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING     #
-- # NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED  #
-- # OF THE POSSIBILITY OF SUCH DAMAGE.                                                            #
-- # ********************************************************************************************* #
-- # The NEORV32 Processor - https://github.com/stnolting/neorv32              (c) Stephan Nolting #
-- #################################################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library neorv32;
use neorv32.neorv32_package.all;
use neorv32.neorv32_application_image.all; -- this file is generated by the image generator
use std.textio.all;

entity neorv32_tb is
end neorv32_tb;

architecture neorv32_tb_rtl of neorv32_tb is

  -- User Configuration ---------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  -- general --
  constant ext_imem_c            : boolean := false; -- false: use and boot from proc-internal IMEM, true: use and boot from external (initialized) simulated IMEM (ext. mem A)
  constant ext_dmem_c            : boolean := false; -- false: use proc-internal DMEM, true: use external simulated DMEM (ext. mem B)
  constant icache_en_c           : boolean := false; -- set true to use processor-internal instruction cache
  constant imem_size_c           : natural := 16*1024; -- size in bytes of processor-internal IMEM / external mem A
  constant dmem_size_c           : natural := 8*1024; -- size in bytes of processor-internal DMEM / external mem B
  constant f_clock_c             : natural := 100000000; -- main clock in Hz
  constant baud_rate_c           : natural := 19200; -- simulation UART output baudrate
  -- simulated external Wishbone memory A (can be used as external IMEM) --
  constant ext_mem_a_base_addr_c : std_ulogic_vector(31 downto 0) := x"00000000"; -- wishbone memory base address (external IMEM base)
  constant ext_mem_a_size_c      : natural := imem_size_c; -- wishbone memory size in bytes
  constant ext_mem_a_latency_c   : natural := 8; -- latency in clock cycles (min 1, max 255), plus 1 cycle initial delay
  -- simulated external Wishbone memory B (can be used as external DMEM) --
  constant ext_mem_b_base_addr_c : std_ulogic_vector(31 downto 0) := x"80000000"; -- wishbone memory base address (external DMEM base)
  constant ext_mem_b_size_c      : natural := dmem_size_c; -- wishbone memory size in bytes
  constant ext_mem_b_latency_c   : natural := 8; -- latency in clock cycles (min 1, max 255), plus 1 cycle initial delay
  -- simulated external Wishbone memory C (can be used as external IO) --
  constant ext_mem_c_base_addr_c : std_ulogic_vector(31 downto 0) := x"F0000000"; -- wishbone memory base address (default begin of EXTERNAL IO area)
  constant ext_mem_c_size_c      : natural := 64; -- wishbone memory size in bytes
  constant ext_mem_c_latency_c   : natural := 3; -- latency in clock cycles (min 1, max 255), plus 1 cycle initial delay
  -- simulation interrupt trigger --
  constant irq_trigger_c         : std_ulogic_vector(31 downto 0) := x"FF000000";
  -- -------------------------------------------------------------------------------------------

  -- internals - hands off! --
  constant int_imem_c : boolean := not ext_imem_c;
  constant int_dmem_c : boolean := not ext_dmem_c;
  constant baud_val_c : real := real(f_clock_c) / real(baud_rate_c);
  constant t_clock_c  : time := (1 sec) / f_clock_c;

  -- text.io --
  file file_uart_tx_out : text open write_mode is "neorv32.testbench_uart.out";

  -- generators --
  signal clk_gen, rst_gen : std_ulogic := '0';

  -- simulation uart receiver --
  signal uart_txd         : std_ulogic;
  signal uart_rx_sync     : std_ulogic_vector(04 downto 0) := (others => '1');
  signal uart_rx_busy     : std_ulogic := '0';
  signal uart_rx_sreg     : std_ulogic_vector(08 downto 0) := (others => '0');
  signal uart_rx_baud_cnt : real;
  signal uart_rx_bitcnt   : natural;

  -- gpio --
  signal gpio : std_ulogic_vector(31 downto 0);

  -- twi --
  signal twi_scl, twi_sda : std_logic;

  -- spi --
  signal spi_data : std_ulogic;

  -- irq --
  signal msi_ring, mei_ring : std_ulogic;
  signal soc_firq_ring      : std_ulogic_vector(7 downto 0);

  -- Wishbone bus --
  type wishbone_t is record
    addr  : std_ulogic_vector(31 downto 0); -- address
    wdata : std_ulogic_vector(31 downto 0); -- master write data
    rdata : std_ulogic_vector(31 downto 0); -- master read data
    we    : std_ulogic; -- write enable
    sel   : std_ulogic_vector(03 downto 0); -- byte enable
    stb   : std_ulogic; -- strobe
    cyc   : std_ulogic; -- valid cycle
    ack   : std_ulogic; -- transfer acknowledge
    err   : std_ulogic; -- transfer error
    tag   : std_ulogic_vector(2 downto 0); -- tag
    lock  : std_ulogic; -- locked/exclusive bus access
  end record;
  signal wb_cpu, wb_mem_a, wb_mem_b, wb_mem_c, wb_irq : wishbone_t;

  -- Wishbone memories --
  type ext_mem_a_ram_t is array (0 to ext_mem_a_size_c/4-1) of std_ulogic_vector(31 downto 0);
  type ext_mem_b_ram_t is array (0 to ext_mem_b_size_c/4-1) of std_ulogic_vector(31 downto 0);
  type ext_mem_c_ram_t is array (0 to ext_mem_c_size_c/4-1) of std_ulogic_vector(31 downto 0);
  type ext_mem_read_latency_t is array (0 to 255) of std_ulogic_vector(31 downto 0);

  -- init function --
  -- impure function: returns NOT the same result every time it is evaluated with the same arguments since the source file might have changed
  impure function init_wbmem(init : application_init_image_t) return ext_mem_a_ram_t is
    variable mem_v : ext_mem_a_ram_t;
  begin
    mem_v := (others => (others => '0'));
    for i in 0 to init'length-1 loop -- init only in range of source data array
      if (xbus_big_endian_c = true) then
        mem_v(i) := init(i);
      else
        mem_v(i) := bswap32_f(init(i));
      end if;
    end loop; -- i
    return mem_v;
  end function init_wbmem;

  -- external memory components --
  signal ext_ram_a : ext_mem_a_ram_t := init_wbmem(application_init_image); -- initialized, used to simulate external IMEM
  signal ext_ram_b : ext_mem_b_ram_t := (others => (others => '0')); -- zero, used to simulate external DMEM
  signal ext_ram_c : ext_mem_c_ram_t; -- uninitialized, used to simulate external IO

  type ext_mem_t is record
    rdata  : ext_mem_read_latency_t;
    acc_en : std_ulogic;
    ack    : std_ulogic_vector(ext_mem_a_latency_c-1 downto 0);
  end record;
  signal ext_mem_a, ext_mem_b, ext_mem_c : ext_mem_t;

begin

  -- Clock/Reset Generator ------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  clk_gen <= not clk_gen after (t_clock_c/2);
  rst_gen <= '0', '1' after 60*(t_clock_c/2);


  -- The Core of the Problem ----------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  neorv32_top_inst: neorv32_top
  generic map (
    -- General --
    CLOCK_FREQUENCY              => f_clock_c,     -- clock frequency of clk_i in Hz
    BOOTLOADER_EN                => false,         -- implement processor-internal bootloader?
    USER_CODE                    => x"12345678",   -- custom user code
    HW_THREAD_ID                 => 0,             -- hardware thread id (hartid) (32-bit)
    -- RISC-V CPU Extensions --
    CPU_EXTENSION_RISCV_A        => true,          -- implement atomic extension?
    CPU_EXTENSION_RISCV_B        => true,          -- implement bit manipulation extensions?
    CPU_EXTENSION_RISCV_C        => true,          -- implement compressed extension?
    CPU_EXTENSION_RISCV_E        => false,         -- implement embedded RF extension?
    CPU_EXTENSION_RISCV_M        => true,          -- implement muld/div extension?
    CPU_EXTENSION_RISCV_U        => true,          -- implement user mode extension?
    CPU_EXTENSION_RISCV_Zicsr    => true,          -- implement CSR system?
    CPU_EXTENSION_RISCV_Zifencei => true,          -- implement instruction stream sync.?
    -- Extension Options --
    FAST_MUL_EN                  => false,         -- use DSPs for M extension's multiplier
    FAST_SHIFT_EN                => false,         -- use barrel shifter for shift operations
    -- Physical Memory Protection (PMP) --
    PMP_NUM_REGIONS              => 4,             -- number of regions (0..64)
    PMP_MIN_GRANULARITY          => 64*1024,       -- minimal region granularity in bytes, has to be a power of 2, min 8 bytes
    -- Hardware Performance Monitors (HPM) --
    HPM_NUM_CNTS                 => 12,            -- number of inmplemnted HPM counters (0..29)
    -- Internal Instruction memory --
    MEM_INT_IMEM_EN              => int_imem_c ,   -- implement processor-internal instruction memory
    MEM_INT_IMEM_SIZE            => imem_size_c,   -- size of processor-internal instruction memory in bytes
    MEM_INT_IMEM_ROM             => false,         -- implement processor-internal instruction memory as ROM
    -- Internal Data memory --
    MEM_INT_DMEM_EN              => int_dmem_c,    -- implement processor-internal data memory
    MEM_INT_DMEM_SIZE            => dmem_size_c,   -- size of processor-internal data memory in bytes
    -- Internal Cache memory --
    ICACHE_EN                    => icache_en_c,   -- implement instruction cache
    ICACHE_NUM_BLOCKS            => 8,             -- i-cache: number of blocks (min 2), has to be a power of 2
    ICACHE_BLOCK_SIZE            => 64,            -- i-cache: block size in bytes (min 4), has to be a power of 2
    ICACHE_ASSOCIATIVITY         => 2,             -- i-cache: associativity / number of sets (1=direct_mapped), has to be a power of 2
    -- External memory interface --
    MEM_EXT_EN                   => true,          -- implement external memory bus interface?
    -- Processor peripherals --
    IO_GPIO_EN                   => true,          -- implement general purpose input/output port unit (GPIO)?
    IO_MTIME_EN                  => true,          -- implement machine system timer (MTIME)?
    IO_UART_EN                   => true,          -- implement universal asynchronous receiver/transmitter (UART)?
    IO_SPI_EN                    => true,          -- implement serial peripheral interface (SPI)?
    IO_TWI_EN                    => true,          -- implement two-wire interface (TWI)?
    IO_PWM_EN                    => true,          -- implement pulse-width modulation unit (PWM)?
    IO_WDT_EN                    => true,          -- implement watch dog timer (WDT)?
    IO_TRNG_EN                   => false,         -- trng cannot be simulated
    IO_CFS_EN                    => true,          -- implement custom functions subsystem (CFS)?
    IO_CFS_CONFIG                => (others => '0'), -- custom CFS configuration generic
    IO_NCO_EN                    => true           -- implement numerically-controlled oscillator (NCO)?
  )
  port map (
    -- Global control --
    clk_i       => clk_gen,         -- global clock, rising edge
    rstn_i      => rst_gen,         -- global reset, low-active, async
    -- Wishbone bus interface (available if MEM_EXT_EN = true) --
    wb_tag_o    => wb_cpu.tag,      -- tag
    wb_adr_o    => wb_cpu.addr,     -- address
    wb_dat_i    => wb_cpu.rdata,    -- read data
    wb_dat_o    => wb_cpu.wdata,    -- write data
    wb_we_o     => wb_cpu.we,       -- read/write
    wb_sel_o    => wb_cpu.sel,      -- byte enable
    wb_stb_o    => wb_cpu.stb,      -- strobe
    wb_cyc_o    => wb_cpu.cyc,      -- valid cycle
    wb_lock_o   => wb_cpu.lock,     -- locked/exclusive bus access
    wb_ack_i    => wb_cpu.ack,      -- transfer acknowledge
    wb_err_i    => wb_cpu.err,      -- transfer error
    -- Advanced memory control signals (available if MEM_EXT_EN = true) --
    fence_o     => open,            -- indicates an executed FENCE operation
    fencei_o    => open,            -- indicates an executed FENCEI operation
    -- GPIO (available if IO_GPIO_EN = true) --
    gpio_o      => gpio,            -- parallel output
    gpio_i      => gpio,            -- parallel input
    -- UART (available if IO_UART_EN = true) --
    uart_txd_o  => uart_txd,        -- UART send data
    uart_rxd_i  => uart_txd,        -- UART receive data
    -- SPI (available if IO_SPI_EN = true) --
    spi_sck_o   => open,            -- SPI serial clock
    spi_sdo_o   => spi_data,        -- controller data out, peripheral data in
    spi_sdi_i   => spi_data,        -- controller data in, peripheral data out
    spi_csn_o   => open,            -- SPI CS
    -- TWI (available if IO_TWI_EN = true) --
    twi_sda_io  => twi_sda,         -- twi serial data line
    twi_scl_io  => twi_scl,         -- twi serial clock line
    -- PWM (available if IO_PWM_EN = true) --
    pwm_o       => open,            -- pwm channels
    -- Custom Functions Subsystem IO --
    cfs_in_i    => (others => '0'), -- custom CFS inputs
    cfs_out_o   => open,            -- custom CFS outputs
    -- NCO output (available if IO_NCO_EN = true) --
    nco_o      => open,             -- numerically-controlled oscillator channels
    -- system time input from external MTIME (available if IO_MTIME_EN = false) --
    mtime_i     => (others => '0'), -- current system time
    -- Interrupts --
    soc_firq_i  => soc_firq_ring,   -- fast interrupt channels
    mtime_irq_i => '0',             -- machine software interrupt, available if IO_MTIME_EN = false
    msw_irq_i   => msi_ring,        -- machine software interrupt
    mext_irq_i  => mei_ring         -- machine external interrupt
  );

  -- TWI termination (pull-ups) --
  twi_scl <= 'H';
  twi_sda <= 'H';


  -- Console UART Receiver ------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  uart_rx_console: process(clk_gen)
    variable i : integer;
    variable l : line;
  begin
    -- "UART" --
    if rising_edge(clk_gen) then
      -- synchronizer --
      uart_rx_sync <= uart_rx_sync(3 downto 0) & uart_txd;
      -- arbiter --
      if (uart_rx_busy = '0') then -- idle
        uart_rx_busy     <= '0';
        uart_rx_baud_cnt <= round(0.5 * baud_val_c);
        uart_rx_bitcnt   <= 9;
        if (uart_rx_sync(4 downto 1) = "1100") then -- start bit? (falling edge)
          uart_rx_busy <= '1';
        end if;
      else
        if (uart_rx_baud_cnt <= 0.0) then
          if (uart_rx_bitcnt = 1) then
            uart_rx_baud_cnt <= round(0.5 * baud_val_c);
          else
            uart_rx_baud_cnt <= round(baud_val_c);
          end if;
          if (uart_rx_bitcnt = 0) then
            uart_rx_busy <= '0'; -- done
            i := to_integer(unsigned(uart_rx_sreg(8 downto 1)));

            if (i < 32) or (i > 32+95) then -- printable char?
              report "NEORV32_TB_UART.TX: (" & integer'image(i) & ")"; -- print code
            else
              report "NEORV32_TB_UART.TX: " & character'val(i); -- print ASCII
            end if;

            if (i = 10) then -- Linux line break
              writeline(file_uart_tx_out, l);
            elsif (i /= 13) then -- Remove additional carriage return
              write(l, character'val(i));
            end if;
          else
            uart_rx_sreg   <= uart_rx_sync(4) & uart_rx_sreg(8 downto 1);
            uart_rx_bitcnt <= uart_rx_bitcnt - 1;
          end if;
        else
          uart_rx_baud_cnt <= uart_rx_baud_cnt - 1.0;
        end if;
      end if;
    end if;
  end process uart_rx_console;


  -- Wishbone Fabric ------------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  -- CPU broadcast signals --
  wb_mem_a.addr  <= wb_cpu.addr;
  wb_mem_a.wdata <= wb_cpu.wdata;
  wb_mem_a.we    <= wb_cpu.we;
  wb_mem_a.sel   <= wb_cpu.sel;
  wb_mem_a.tag   <= wb_cpu.tag;
  wb_mem_a.cyc   <= wb_cpu.cyc;
  wb_mem_a.lock  <= wb_cpu.lock;

  wb_mem_b.addr  <= wb_cpu.addr;
  wb_mem_b.wdata <= wb_cpu.wdata;
  wb_mem_b.we    <= wb_cpu.we;
  wb_mem_b.sel   <= wb_cpu.sel;
  wb_mem_b.tag   <= wb_cpu.tag;
  wb_mem_b.cyc   <= wb_cpu.cyc;
  wb_mem_b.lock  <= wb_cpu.lock;

  wb_mem_c.addr  <= wb_cpu.addr;
  wb_mem_c.wdata <= wb_cpu.wdata;
  wb_mem_c.we    <= wb_cpu.we;
  wb_mem_c.sel   <= wb_cpu.sel;
  wb_mem_c.tag   <= wb_cpu.tag;
  wb_mem_c.cyc   <= wb_cpu.cyc;
  wb_mem_c.lock  <= wb_cpu.lock;

  wb_irq.addr    <= wb_cpu.addr;
  wb_irq.wdata   <= wb_cpu.wdata;
  wb_irq.we      <= wb_cpu.we;
  wb_irq.sel     <= wb_cpu.sel;
  wb_irq.tag     <= wb_cpu.tag;
  wb_irq.cyc     <= wb_cpu.cyc;
  wb_irq.lock    <= wb_cpu.lock;

  -- CPU read-back signals (no mux here since peripherals have "output gates") --
  wb_cpu.rdata <= wb_mem_a.rdata or wb_mem_b.rdata or wb_mem_c.rdata or wb_irq.rdata;
  wb_cpu.ack   <= wb_mem_a.ack   or wb_mem_b.ack   or wb_mem_c.ack   or wb_irq.ack;
  wb_cpu.err   <= wb_mem_a.err   or wb_mem_b.err   or wb_mem_c.err   or wb_irq.err;

  -- peripheral select via STROBE signal --
  wb_mem_a.stb <= wb_cpu.stb when (wb_cpu.addr >= ext_mem_a_base_addr_c) and (wb_cpu.addr < std_ulogic_vector(unsigned(ext_mem_a_base_addr_c) + ext_mem_a_size_c)) else '0';
  wb_mem_b.stb <= wb_cpu.stb when (wb_cpu.addr >= ext_mem_b_base_addr_c) and (wb_cpu.addr < std_ulogic_vector(unsigned(ext_mem_b_base_addr_c) + ext_mem_b_size_c)) else '0';
  wb_mem_c.stb <= wb_cpu.stb when (wb_cpu.addr >= ext_mem_c_base_addr_c) and (wb_cpu.addr < std_ulogic_vector(unsigned(ext_mem_c_base_addr_c) + ext_mem_c_size_c)) else '0';
  wb_irq.stb   <= wb_cpu.stb when (wb_cpu.addr =  irq_trigger_c) else '0';


  -- Wishbone Memory A (simulated external IMEM) --------------------------------------------
  -- -------------------------------------------------------------------------------------------
  ext_mem_a_access: process(clk_gen)
  begin
    if rising_edge(clk_gen) then
      -- control --
      ext_mem_a.ack(0) <= wb_mem_a.cyc and wb_mem_a.stb; -- wishbone acknowledge

      -- write access --
      if ((wb_mem_a.cyc and wb_mem_a.stb and wb_mem_a.we) = '1') then -- valid write access
        for i in 0 to 3 loop
          if (wb_mem_a.sel(i) = '1') then
            ext_ram_a(to_integer(unsigned(wb_mem_a.addr(index_size_f(ext_mem_a_size_c/4)+1 downto 2))))(7+i*8 downto 0+i*8) <= wb_mem_a.wdata(7+i*8 downto 0+i*8);
          end if;
        end loop; -- i
      end if;

      -- read access --
      ext_mem_a.rdata(0) <= ext_ram_a(to_integer(unsigned(wb_mem_a.addr(index_size_f(ext_mem_a_size_c/4)+1 downto 2)))); -- word aligned
      -- virtual read and ack latency --
      if (ext_mem_a_latency_c > 1) then
        for i in 1 to ext_mem_a_latency_c-1 loop
          ext_mem_a.rdata(i) <= ext_mem_a.rdata(i-1);
          ext_mem_a.ack(i)   <= ext_mem_a.ack(i-1) and wb_mem_a.cyc;
        end loop;
      end if;

      -- bus output register --
      wb_mem_a.err <= '0';
      if (ext_mem_a.ack(ext_mem_a_latency_c-1) = '1') and (wb_mem_b.cyc = '1') then
        wb_mem_a.rdata <= ext_mem_a.rdata(ext_mem_a_latency_c-1);
        wb_mem_a.ack   <= '1';
      else
        wb_mem_a.rdata <= (others => '0');
        wb_mem_a.ack   <= '0';
      end if;
    end if;
  end process ext_mem_a_access;


  -- Wishbone Memory B (simulated external DMEM) --------------------------------------------
  -- -------------------------------------------------------------------------------------------
  ext_mem_b_access: process(clk_gen)
  begin
    if rising_edge(clk_gen) then
      -- control --
      ext_mem_b.ack(0) <= wb_mem_b.cyc and wb_mem_b.stb; -- wishbone acknowledge

      -- write access --
      if ((wb_mem_b.cyc and wb_mem_b.stb and wb_mem_b.we) = '1') then -- valid write access
        for i in 0 to 3 loop
          if (wb_mem_b.sel(i) = '1') then
            ext_ram_b(to_integer(unsigned(wb_mem_b.addr(index_size_f(ext_mem_b_size_c/4)+1 downto 2))))(7+i*8 downto 0+i*8) <= wb_mem_b.wdata(7+i*8 downto 0+i*8);
          end if;
        end loop; -- i
      end if;

      -- read access --
      ext_mem_b.rdata(0) <= ext_ram_b(to_integer(unsigned(wb_mem_b.addr(index_size_f(ext_mem_b_size_c/4)+1 downto 2)))); -- word aligned
      -- virtual read and ack latency --
      if (ext_mem_b_latency_c > 1) then
        for i in 1 to ext_mem_b_latency_c-1 loop
          ext_mem_b.rdata(i) <= ext_mem_b.rdata(i-1);
          ext_mem_b.ack(i)   <= ext_mem_b.ack(i-1) and wb_mem_b.cyc;
        end loop;
      end if;

      -- bus output register --
      wb_mem_b.err <= '0';
      if (ext_mem_b.ack(ext_mem_b_latency_c-1) = '1') and (wb_mem_b.cyc = '1') then
        wb_mem_b.rdata <= ext_mem_b.rdata(ext_mem_b_latency_c-1);
        wb_mem_b.ack   <= '1';
      else
        wb_mem_b.rdata <= (others => '0');
        wb_mem_b.ack   <= '0';
      end if;
    end if;
  end process ext_mem_b_access;


  -- Wishbone Memory C (simulated external IO) ----------------------------------------------
  -- -------------------------------------------------------------------------------------------
  ext_mem_c_access: process(clk_gen)
  begin
    if rising_edge(clk_gen) then
      -- control --
      ext_mem_c.ack(0) <= wb_mem_c.cyc and wb_mem_c.stb; -- wishbone acknowledge

      -- write access --
      if ((wb_mem_c.cyc and wb_mem_c.stb and wb_mem_c.we) = '1') then -- valid write access
        for i in 0 to 3 loop
          if (wb_mem_c.sel(i) = '1') then
            ext_ram_c(to_integer(unsigned(wb_mem_c.addr(index_size_f(ext_mem_c_size_c/4)+1 downto 2))))(7+i*8 downto 0+i*8) <= wb_mem_c.wdata(7+i*8 downto 0+i*8);
          end if;
        end loop; -- i
      end if;

      -- read access --
      ext_mem_c.rdata(0) <= ext_ram_c(to_integer(unsigned(wb_mem_c.addr(index_size_f(ext_mem_c_size_c/4)+1 downto 2)))); -- word aligned
      -- virtual read and ack latency --
      if (ext_mem_c_latency_c > 1) then
        for i in 1 to ext_mem_c_latency_c-1 loop
          ext_mem_c.rdata(i) <= ext_mem_c.rdata(i-1);
          ext_mem_c.ack(i)   <= ext_mem_c.ack(i-1) and wb_mem_c.cyc;
        end loop;
      end if;

      -- error to simulate interrupted LOCKED/EXCLUSIVE bus access --
      wb_mem_c.err <= wb_mem_c.cyc and wb_mem_c.stb and wb_mem_c.lock and wb_mem_c.addr(2); -- locked access to odd word-addresses will fail

      -- bus output register --
      if (ext_mem_c.ack(ext_mem_c_latency_c-1) = '1') and (wb_mem_c.cyc = '1') then
        wb_mem_c.rdata <= ext_mem_c.rdata(ext_mem_c_latency_c-1);
        wb_mem_c.ack   <= '1';
      else
        wb_mem_c.rdata <= (others => '0');
        wb_mem_c.ack   <= '0';
      end if;
    end if;
  end process ext_mem_c_access;


  -- Wishbone IRQ Triggers ------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  irq_trigger: process(clk_gen)
  begin
    if rising_edge(clk_gen) then
      -- bus interface --
      wb_irq.rdata  <= (others => '0');
      wb_irq.ack    <= wb_irq.cyc and wb_irq.stb and wb_irq.we and and_all_f(wb_irq.sel);
      wb_irq.err    <= '0';
      -- trigger IRQ using CSR.MIE bit layout --
      msi_ring      <= '0';
      mei_ring      <= '0';
      soc_firq_ring <= (others => '0');
      if ((wb_irq.cyc and wb_irq.stb and wb_irq.we and and_all_f(wb_irq.sel)) = '1') then
        msi_ring         <= wb_irq.wdata(03); -- machine software interrupt
        mei_ring         <= wb_irq.wdata(11); -- machine software interrupt
        soc_firq_ring(0) <= wb_irq.wdata(24); -- fast interrupt SoC channel 0
        soc_firq_ring(1) <= wb_irq.wdata(25); -- fast interrupt SoC channel 1
        soc_firq_ring(2) <= wb_irq.wdata(26); -- fast interrupt SoC channel 2
        soc_firq_ring(3) <= wb_irq.wdata(27); -- fast interrupt SoC channel 3
        soc_firq_ring(4) <= wb_irq.wdata(28); -- fast interrupt SoC channel 4
        soc_firq_ring(5) <= wb_irq.wdata(29); -- fast interrupt SoC channel 5
        soc_firq_ring(6) <= wb_irq.wdata(30); -- fast interrupt SoC channel 6
        soc_firq_ring(7) <= wb_irq.wdata(31); -- fast interrupt SoC channel 7
      end if;
    end if;
  end process irq_trigger;


end neorv32_tb_rtl;
