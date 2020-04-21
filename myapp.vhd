----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    14:58:00 21/11/2019 
-- Design Name: 
-- Module Name:    memory_ctl - Behavioral 
-- Project Name:  Research_project - Remote Reconfiguration
-- Target Devices: Xilinx spartan6 -FPGA
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--


-- Start with the signal declarations
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--~ library std;
--~ use std.textio.all;

--~ library work;
--~ use work.math.all;
--~ use work.print.all;
--~ use work.uart_sim.all;
--~ use work.conditional_select.all;

entity flash_mem_ctrl is
    port
    (
        -- system
        clk         : in  std_logic; -- TODO: max frequency?
        rst         : in  std_logic;
        
        -- flash
        flash_rp    : out std_logic;
        flash_cs    : out std_logic;
        flash_oe    : out std_logic;
        flash_we    : out std_logic;
        flash_addr  : out std_logic_vector(25 downto 0);
        flash_data  : inout std_logic_vector(15 downto 0);
        
		debug_data  : out std_logic_vector(15 downto 0);
		debug_we 	: out std_logic;
        -- control
        rst_flash   : in  std_logic;
        cmd         : in  std_logic_vector(3 downto 0);
        start       : in  std_logic;
		wb_next     : out std_logic;
        finish      : out std_logic;
        addr        : in  std_logic_vector(25 downto 0);
        din         : in  std_logic_vector(15 downto 0);
        dout        : out std_logic_vector(15 downto 0)
    );
end entity flash_mem_ctrl;

architecture DESCRIPTION of flash_mem_ctrl is
    
    ------------------------------
    -- constants
    ------------------------------
    
    constant CMD_WRITE_DATA         : std_logic_vector(3 downto 0) := x"1"; -- "0001";
    constant CMD_WRITE_BLOCK        : std_logic_vector(3 downto 0) := x"2"; -- "0010";
    constant CMD_READ_DATA          : std_logic_vector(3 downto 0) := x"3"; -- "0011";
    constant CMD_READ_STATUS_REG    : std_logic_vector(3 downto 0) := x"4"; -- "0100";
    constant CMD_CLEAR_STATUS_REG   : std_logic_vector(3 downto 0) := x"5"; -- "0101";
    constant CMD_LOCK_STATUS        : std_logic_vector(3 downto 0) := x"6"; -- "0110";
    constant CMD_UNLOCK_BLOCK       : std_logic_vector(3 downto 0) := x"7"; -- "0111";
    constant CMD_ERASE_BLOCK        : std_logic_vector(3 downto 0) := x"8"; -- "1000";
    constant CMD_SUSPEND            : std_logic_vector(3 downto 0) := x"9"; -- "1001";
    constant CMD_RESUME             : std_logic_vector(3 downto 0) := x"a"; -- "1010";
	constant CMD_LOCK_BLOCK         : std_logic_vector(3 downto 0) := x"b"; -- "1011";	
    -- commands "1000" - "1111" reserved for future use
    
    ------------------------------
    -- type definitions
    ------------------------------
    
    type states is
    (
        ST_IDLE,
        
        -- write data
        ST_WR_SETUP_0,
        ST_WR_SETUP_1,
        ST_WR_DATA_0,
        ST_WR_DATA_1,
        
        -- write block
        ST_WB_SETUP_0,
        ST_WB_SETUP_1,
        ST_WB_COUNT_0,
        ST_WB_COUNT_1,
        ST_WB_DATA_0,
        ST_WB_DATA_1,
        ST_WB_CONFIRM_0,
        ST_WB_CONFIRM_1,
        
        -- read / clear status register
        ST_SR_SETUP_0,
        ST_SR_SETUP_1,
        ST_SR_READ_0,
        ST_SR_READ_1,
        ST_SR_CLEAR_0,
        ST_SR_CLEAR_1,
        
        -- suspend / resume
        ST_SUSPEND_0,
        ST_SUSPEND_1,
        ST_RESUME_0,
        ST_RESUME_1,
        
        -- erase block
        ST_EB_SETUP_0,
        ST_EB_SETUP_1,
        ST_EB_CONFIRM_0,
        ST_EB_CONFIRM_1,
        
        -- unlock block
        ST_UB_SETUP_0,
        ST_UB_SETUP_1,
        ST_UB_CONFIRM_0,
        ST_UB_CONFIRM_1,
        
		-- lock block
        ST_LB_SETUP_0,
        ST_LB_SETUP_1,
        ST_LB_CONFIRM_0,
        ST_LB_CONFIRM_1,
		
        -- block lock status
        ST_LS_SETUP_0,
        ST_LS_SETUP_1,
        ST_LS_READ_0,
        ST_LS_READ_1,
        
        -- read data
        ST_RD_SETUP_0,
        ST_RD_SETUP_1,
        ST_RD_DATA_0,
        ST_RD_DATA_1
        
        --~ -- sync with external logic
        --~ ST_SYNC
    );
    
    signal curr_state       : states;
    signal next_state       : states;
	
	signal reg_count        : unsigned(15 downto 0);
    signal load_count       : std_logic;
    signal decr_count       : std_logic;
    --signal reg_length       : unsigned(15 downto 0);
    
begin

	debug_data <= cmd & flash_data(11 downto 0);
    debug_we <= '1' when curr_state = ST_WR_SETUP_1 or
                         curr_state = ST_WR_DATA_1 or
                         curr_state = ST_WB_SETUP_1 or
                         curr_state = ST_WB_COUNT_1 or
                         curr_state = ST_WB_DATA_1 or
                         curr_state = ST_WB_CONFIRM_1 or
						 (curr_state = ST_SR_READ_1 and flash_data(7) = '1') or
                         curr_state = ST_SR_CLEAR_1 or
                         curr_state = ST_SUSPEND_1 or
                         curr_state = ST_RESUME_1 or
                         curr_state = ST_EB_SETUP_1 or
                         curr_state = ST_EB_CONFIRM_1 or
                         curr_state = ST_UB_SETUP_1 or
                         curr_state = ST_UB_CONFIRM_1 or
						  curr_state = ST_LB_SETUP_1 or
                         curr_state = ST_LB_CONFIRM_1 or
                         curr_state = ST_LS_SETUP_1 or
                         curr_state = ST_LS_READ_1 or
                         curr_state = ST_RD_SETUP_1 or
                         curr_state = ST_RD_DATA_1 else '0';


    flash_rp <= not rst_flash;
    
    P_STATES : process (clk, rst)
    begin
        if rst = '1' then
            curr_state <= ST_IDLE;
        else
            if rising_edge(clk) then
                curr_state <= next_state;
            end if;
        end if;
    end process;

    P_FSM : process (curr_state, flash_data, din, start, cmd, addr, reg_count)
    begin
        -- signals (default values)
        flash_oe <= '1';
        flash_we <= '1';
        flash_cs <= '1';
        
        flash_addr <= (others => '0');
        flash_data <= (others => 'Z');
        
        load_count <= '0';
        decr_count <= '0';
        
        dout <= (others => '0');
        finish <= '0';
        wb_next <= '0';
        
		
		load_count <= '0';
        decr_count <= '0';
        -- calc next state
        case curr_state is
            
            when ST_IDLE =>
                if start = '1' then
                    if    cmd = CMD_WRITE_DATA       then next_state <= ST_WR_SETUP_0;
					elsif cmd = CMD_WRITE_BLOCK      then next_state <= ST_WB_SETUP_0; load_count <= '1';
                    elsif cmd = CMD_READ_DATA        then next_state <= ST_RD_SETUP_0;
                    elsif cmd = CMD_READ_STATUS_REG  then next_state <= ST_SR_SETUP_0;
                    elsif cmd = CMD_CLEAR_STATUS_REG then next_state <= ST_SR_CLEAR_0;
                    elsif cmd = CMD_LOCK_STATUS      then next_state <= ST_LS_SETUP_0;
                    elsif cmd = CMD_UNLOCK_BLOCK     then next_state <= ST_UB_SETUP_0;
                    elsif cmd = CMD_ERASE_BLOCK      then next_state <= ST_EB_SETUP_0;
					elsif cmd = CMD_LOCK_BLOCK       then next_state <= ST_LB_SETUP_0;					
                    else
                        next_state <= ST_IDLE;                        
                    end if;
                else
                    next_state <= ST_IDLE;
                end if;
                
            ------------------------------
            -- write data
            ------------------------------
            
            when ST_WR_SETUP_0 =>
                flash_we <= '0';
                flash_cs <= '0';
                flash_addr <= addr;
                flash_data <= x"0040";
                next_state <= ST_WR_SETUP_1;
                
            when ST_WR_SETUP_1 =>
                flash_addr <= addr;
                flash_data <= x"0040";
                next_state <= ST_WR_DATA_0;
            
            when ST_WR_DATA_0 =>
                flash_we <= '0';
                flash_cs <= '0';
                flash_addr <= addr;
                flash_data <= din;
                next_state <= ST_WR_DATA_1;
                
            when ST_WR_DATA_1 =>
                flash_addr <= addr;
                flash_data <= din;
                next_state <= ST_SR_SETUP_0;
        
		
			------------------------------
            -- write block
            ------------------------------
            
            when ST_WB_SETUP_0 =>
                flash_we <= '0';
                flash_cs <= '0';
                flash_addr <= addr;
                flash_data <= x"00e8";
                next_state <= ST_WB_SETUP_1;
                
            when ST_WB_SETUP_1 =>
                flash_addr <= addr;
                flash_data <= x"00e8";
                next_state <= ST_WB_COUNT_0;
                
            when ST_WB_COUNT_0 =>
                flash_we <= '0';
                flash_cs <= '0';
                flash_addr <= addr;
                flash_data <= std_logic_vector(reg_count);
                next_state <= ST_WB_COUNT_1;
                
            when ST_WB_COUNT_1 =>
                flash_addr <= addr;
                flash_data <= std_logic_vector(reg_count);
                next_state <= ST_WB_DATA_0;
            
            when ST_WB_DATA_0 =>
                flash_we <= '0';
                flash_cs <= '0';
                flash_addr <= addr;
                --~ flash_addr <= addr(25 downto 16) & std_logic_vector(reg_length - reg_count);
                flash_data <= din;
                next_state <= ST_WB_DATA_1;
                
            when ST_WB_DATA_1 =>
                flash_addr <= addr;
                --~ flash_addr <= addr(25 downto 16) & std_logic_vector(reg_length - reg_count);
                flash_data <= din;
                if reg_count = 0 then
                    next_state <= ST_WB_CONFIRM_0;
                else
                    wb_next <= '1';
                    decr_count <= '1';
                    next_state <= ST_WB_DATA_0;
                end if;
                
            when ST_WB_CONFIRM_0 =>
                flash_we <= '0';
                flash_cs <= '0';
                flash_addr <= addr;
                flash_data <= x"00d0";
                next_state <= ST_WB_CONFIRM_1;
                
            when ST_WB_CONFIRM_1 =>
                flash_addr <= addr;
                flash_data <= x"00d0";
                next_state <= ST_SR_SETUP_0;
		
            ------------------------------
            -- read data
            ------------------------------
            
            when ST_RD_SETUP_0 =>
                flash_we <= '0';
                flash_cs <= '0';
                flash_addr <= addr;
                flash_data <= x"00ff";
                next_state <= ST_RD_SETUP_1;
                
            when ST_RD_SETUP_1 =>
                flash_addr <= addr;
                flash_data <= x"00ff";
                next_state <= ST_RD_DATA_0;
            
            when ST_RD_DATA_0 =>
                flash_oe <= '0';
                flash_cs <= '0';
                flash_addr <= addr;
                next_state <= ST_RD_DATA_1;
                
            when ST_RD_DATA_1 =>
                flash_oe <= '0';
                flash_cs <= '0';
                flash_addr <= addr;
                finish <= '1';
                dout <= flash_data;
                next_state <= ST_IDLE;
            
            ------------------------------
            -- read / clear status register
            ------------------------------
                
            when ST_SR_SETUP_0 =>
                flash_we <= '0';
                flash_cs <= '0';
                flash_data <= x"0070";
                next_state <= ST_SR_SETUP_1;
                
            when ST_SR_SETUP_1 =>
                flash_data <= x"0070";
                next_state <= ST_SR_READ_0;
            
            when ST_SR_READ_0 =>
                flash_oe <= '0';
                flash_cs <= '0';
                next_state <= ST_SR_READ_1;
                
            when ST_SR_READ_1 =>
                if flash_data(7) = '1' then
                    finish <= '1';
                    dout <= flash_data;
                    next_state <= ST_IDLE;
                else
                    next_state <= ST_SR_SETUP_0;
                end if;
                
            when ST_SR_CLEAR_0 =>
                flash_we <= '0';
                flash_cs <= '0';
                flash_data <= x"0050";
                next_state <= ST_SR_CLEAR_1;
            
            when ST_SR_CLEAR_1 =>
                flash_data <= x"0050";
                finish <= '1';
                next_state <= ST_IDLE;
                
            ------------------------------
            -- erase block
            ------------------------------
            
            when ST_EB_SETUP_0 =>
                flash_we <= '0';
                flash_cs <= '0';
                flash_addr <= addr;
                flash_data <= x"0020";
                next_state <= ST_EB_SETUP_1;
                
            when ST_EB_SETUP_1 =>
                flash_addr <= addr;
                flash_data <= x"0020";
                next_state <= ST_EB_CONFIRM_0;
                
            when ST_EB_CONFIRM_0 =>
                flash_we <= '0';
                flash_cs <= '0';
                flash_addr <= addr;
                flash_data <= x"00d0";
                next_state <= ST_EB_CONFIRM_1;
                
            when ST_EB_CONFIRM_1 =>
                flash_addr <= addr;
                flash_data <= x"00d0";
                next_state <= ST_SR_SETUP_0;
                
            ------------------------------
            -- block lock status
            ------------------------------
            
            when ST_LS_SETUP_0 =>
                flash_we <= '0';
                flash_cs <= '0';
                flash_addr(25 downto 16) <= addr(25 downto 16);
                flash_addr(15 downto  0) <= x"0002";
                flash_data <= x"0090";
                next_state <= ST_LS_SETUP_1;
            
            when ST_LS_SETUP_1 =>
                flash_addr(25 downto 16) <= addr(25 downto 16);
                flash_addr(15 downto  0) <= x"0002";
                flash_data <= x"0090";
                next_state <= ST_LS_READ_0;
            
            when ST_LS_READ_0 =>
                flash_oe <= '0';
                flash_cs <= '0';
                flash_addr(25 downto 16) <= addr(25 downto 16);
                flash_addr(15 downto  0) <= x"0002";
                dout <= flash_data;
                next_state <= ST_LS_READ_1;
            
            when ST_LS_READ_1 =>
                flash_addr(25 downto 16) <= addr(25 downto 16);
                flash_addr(15 downto  0) <= x"0002";
                dout <= flash_data;
                finish <= '1';
                next_state <= ST_IDLE;
                
            ------------------------------
            -- unlock block
            ------------------------------
            
            when ST_UB_SETUP_0 =>
                flash_we <= '0';
                flash_cs <= '0';
                flash_addr <= addr;
                flash_data <= x"0060";
                next_state <= ST_UB_SETUP_1;
            
            when ST_UB_SETUP_1 =>
                flash_addr <= addr;
                flash_data <= x"0060";
                next_state <= ST_UB_CONFIRM_0;
                
            when ST_UB_CONFIRM_0 =>
                flash_we <= '0';
                flash_cs <= '0';
                flash_addr <= addr;
                flash_data <= x"00d0";
                next_state <= ST_UB_CONFIRM_1;
            
            when ST_UB_CONFIRM_1 =>
                flash_addr <= addr;
                flash_data <= x"00d0";
                finish <= '1';
                next_state <= ST_IDLE;
                
			------------------------------
            -- lock block
            ------------------------------
            
            when ST_LB_SETUP_0 =>
                flash_we <= '0';
                flash_cs <= '0';
                flash_addr <= addr;
                flash_data <= x"0060";
                next_state <= ST_LB_SETUP_1;
            
            when ST_LB_SETUP_1 =>
                flash_addr <= addr;
                flash_data <= x"0060";
                next_state <= ST_LB_CONFIRM_0;
                
            when ST_LB_CONFIRM_0 =>
                flash_we <= '0';
                flash_cs <= '0';
                flash_addr <= addr;
                flash_data <= x"0001";
                next_state <= ST_LB_CONFIRM_1;
            
            when ST_LB_CONFIRM_1 =>
                flash_addr <= addr;
                flash_data <= x"0001";
                finish <= '1';
                next_state <= ST_IDLE;	
			
				
            when others =>
                next_state <= ST_IDLE;
        
        end case;
    end process;
	
	
	-- ######################################
    -- #                                    #
    -- #            Count Register          #
    -- #                                    #
    -- ######################################
    
    process (clk, rst, load_count, decr_count)
    begin
        if rst = '1' then
            reg_count <= (others => '0');
            --reg_length <= (others => '0');
        else
            if rising_edge(clk) then
                
                if load_count = '1' then
                    reg_count <= unsigned(din);
                    --reg_length <= unsigned(din);
                end if;
                
                if decr_count = '1' then
                    reg_count <= reg_count - 1;
                end if;
                
            end if;
        end if;
    end process;
    
end architecture;
