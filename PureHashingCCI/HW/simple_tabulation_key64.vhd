library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity simple_tabulation_key64 is
port (
	clk : in std_logic;
	resetn : in std_logic;
	req_hash : in std_logic;
	populate : in std_logic;
	in_data : in std_logic_vector(63 downto 0);
	out_valid : out std_logic;
	out_data : out std_logic_vector(31 downto 0));
end simple_tabulation_key64;

architecture behavioral of simple_tabulation_key64 is

type mem_en_signals is array (7 downto 0) of std_logic;
type mem_addr_signals is array (7 downto 0) of std_logic_vector(7 downto 0);
type mem_data_signals is array (7 downto 0) of std_logic_vector(31 downto 0);

signal write_en : mem_en_signals;
signal read_en : mem_en_signals;
signal write_addr : mem_addr_signals;
signal read_addr: mem_addr_signals;
signal mem_data_out : mem_data_signals;
signal mem_data_in : mem_data_signals;

signal requested : std_logic := '0';
signal requested_1d : std_logic := '0';

component spl_sdp_mem
	generic (
		DATA_WIDTH : integer := 32;
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

begin

TABLE_GEN: for i in 0 to 7 generate
	tablex: spl_sdp_mem
	generic map (
		DATA_WIDTH => 32,
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


process(clk)
begin
if clk'event and clk = '1' then
	if resetn = '0' then
		requested <= '0';
		requested_1d <= '0';
		write_en <= (others => '0');
		read_en <= (others => '0');
		write_addr <= (others => (others => '0'));
		read_addr <= (others => (others => '0'));
		mem_data_in <= (others => (others => '0'));
		out_valid <= '0';
		out_data <= (others => '0');
	else
		requested <= '0';
		read_en <= (others => '0');
		write_en <= (others => '0');
		if req_hash = '1' then
			if populate = '1' then -- populate table
				case in_data(42 downto 40) is
					when B"000" => 
						write_en(0) <= '1';
						write_addr(0) <= in_data(39 downto 32);
						mem_data_in(0) <= in_data(31 downto 0);
					when B"001" => 
						write_en(1) <= '1';
						write_addr(1) <= in_data(39 downto 32);
						mem_data_in(1) <= in_data(31 downto 0);
					when B"010" =>
						write_en(2) <= '1';
						write_addr(2) <= in_data(39 downto 32);
						mem_data_in(2) <= in_data(31 downto 0);
					when B"011" =>
						write_en(3) <= '1';
						write_addr(3) <= in_data(39 downto 32);
						mem_data_in(3) <= in_data(31 downto 0);
					when B"100" => 
						write_en(4) <= '1';
						write_addr(4) <= in_data(39 downto 32);
						mem_data_in(4) <= in_data(31 downto 0);
					when B"101" =>
						write_en(5) <= '1';
						write_addr(5) <= in_data(39 downto 32);
						mem_data_in(5) <= in_data(31 downto 0);
					when B"110" =>
						write_en(6) <= '1';
						write_addr(6) <= in_data(39 downto 32);
						mem_data_in(6) <= in_data(31 downto 0);
					when B"111" =>
						write_en(7) <= '1';
						write_addr(7) <= in_data(39 downto 32);
						mem_data_in(7) <= in_data(31 downto 0);
					when others => 
						write_en <= (others => '0');
						write_addr <= (others => (others => '0'));
						mem_data_in <= (others => (others => '0'));
				end case;
			else -- hash key
				requested <= '1';
				read_en <= (others => '1');
				read_addr(0) <= in_data(7 downto 0);
				read_addr(1) <= in_data(15 downto 8);
				read_addr(2) <= in_data(23 downto 16);
				read_addr(3) <= in_data(31 downto 24);
				read_addr(4) <= in_data(39 downto 32);
				read_addr(5) <= in_data(47 downto 40);
				read_addr(6) <= in_data(55 downto 48);
				read_addr(7) <= in_data(63 downto 56);
				--read_addr(7) <= in_data(7 downto 0);
				--read_addr(6) <= in_data(15 downto 8);
				--read_addr(5) <= in_data(23 downto 16);
				--read_addr(4) <= in_data(31 downto 24);
				--read_addr(3) <= in_data(39 downto 32);
				--read_addr(2) <= in_data(47 downto 40);
				--read_addr(1) <= in_data(55 downto 48);
				--read_addr(0) <= in_data(63 downto 56);
			end if;
		end if;

		out_valid <= '0';
		if requested_1d = '1' then
			out_valid <= '1';
			out_data <= mem_data_out(0) xor
						mem_data_out(1) xor
						mem_data_out(2) xor
						mem_data_out(3) xor
						mem_data_out(4) xor
						mem_data_out(5) xor
						mem_data_out(6) xor
						mem_data_out(7);
		end if;

		requested_1d <= requested;
	end if;
end if;
end process;

end behavioral;