library ieee;
library std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity hash_function_h20bit is
port (
	clk : in std_logic;
	resetn : in std_logic;
	req_hash : in std_logic;
	in_data : in std_logic_vector(511 downto 0);
	out_valid : out std_logic;
	out_data : out std_logic_vector(19 downto 0));
end hash_function_h20bit;

architecture behavioral of hash_function_h20bit is

component spl_sdp_mem
	generic (
		DATA_WIDTH : integer := 20;
		ADDR_WIDTH : integer := 8);
	port (
		clk : in std_logic;
		we : in std_logic;
		re : in std_logic;
		waddr : in std_logic_vector(ADDR_WIDTH-1 downto 0);
		raddr : in std_logic_vector(ADDR_WIDTH-1 downto 0);
		din : in std_logic_vector(DATA_WIDTH-1 downto 0);
		dout : out std_logic_vector(DATA_WIDTH-1 downto 0));
end component;

type mem_en_signals is array (3 downto 0) of std_logic;
type mem_addr_signals is array (3 downto 0) of std_logic_vector(7 downto 0);
type mem_data_signals is array (3 downto 0) of std_logic_vector(19 downto 0);

signal write_en : mem_en_signals;
signal read_en : mem_en_signals;
signal write_addr : mem_addr_signals;
signal read_addr: mem_addr_signals;
signal mem_data_out : mem_data_signals;
signal mem_data_in : mem_data_signals;

signal requested : std_logic := '0';
signal populate : integer := 0;

begin

TABLE_GEN: for i in 0 to 3 generate
	tablex: spl_sdp_mem
	generic map (
		DATA_WIDTH => 20,
		ADDR_WIDTH => 8)
	port map (
		clk => clk,
		we => write_en(i),
		re => read_en(i),
		waddr => write_addr(i),
		raddr => read_addr(i),
		din => mem_data_in(i),
		dout => mem_data_out(i));
end generate TABLE_GEN;

table_populate: process(clk)
file random_data_file : TEXT open read_mode is "/home/kkara/Projects/harp-applications/hashtable-cci/HW2/random_data20bit.txt";
variable l : line;
variable temp : integer;
begin
if clk'event and clk = '1' then
	if resetn = '0' then
		populate <= 0;
	else
		if populate < 256 then
			write_en <= (others => '1');
			write_addr <= (others => std_logic_vector(to_unsigned(populate, 8)));
			
			readline(random_data_file, l);
			read(l, temp);
			mem_data_in(0) <= std_logic_vector(to_unsigned(temp, 20));
			readline(random_data_file, l);
			read(l, temp);
			mem_data_in(1) <= std_logic_vector(to_unsigned(temp, 20));
			readline(random_data_file, l);
			read(l, temp);
			mem_data_in(2) <= std_logic_vector(to_unsigned(temp, 20));
			readline(random_data_file, l);
			read(l, temp);
			mem_data_in(3) <= std_logic_vector(to_unsigned(temp, 20));
			
			populate <= populate + 1;
		else
			write_en <= (others => '0');
		end if;
	end if;
end if;
end process;


process(clk)
begin
if clk'event and clk = '1' then
	if resetn = '0' then
		requested <= '0';
	else
		if req_hash = '1' then
			requested <= '1';
			read_addr(0) <= in_data(7 downto 0);
			read_addr(1) <= in_data(15 downto 8);
			read_addr(2) <= in_data(23 downto 16);
			read_addr(3) <= in_data(31 downto 24);
			read_en <= (others => '1');
		else
			requested <= '0';
			read_en <= (others => '0');
		end if;
		if requested = '1' then
			out_valid <= '1';
		else
			out_valid <= '0';
		end if;
	end if;
end if;
end process;

out_data <= mem_data_out(0) xor
			mem_data_out(1) xor
			mem_data_out(2) xor
			mem_data_out(3);

	
end behavioral;