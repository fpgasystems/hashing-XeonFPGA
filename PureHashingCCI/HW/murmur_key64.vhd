library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity murmur_key64 is
port (
	clk : in std_logic;
	resetn : in std_logic;
	req_hash : in std_logic;
	in_data : in std_logic_vector(63 downto 0);
	out_valid : out std_logic;
	out_data : out std_logic_vector(31 downto 0));
end murmur_key64;

architecture behavioral of murmur_key64 is

signal requested1 : std_logic;
signal requested2 : std_logic;
signal requested3 : std_logic;
signal requested4 : std_logic;
signal requested5 : std_logic;

signal key1 : unsigned(63 downto 0);
signal bitshift_key1 : unsigned(63 downto 0);
signal xor_key1 : unsigned(63 downto 0);
signal mult_key1 : unsigned(127 downto 0);

signal key2 : unsigned(63 downto 0);
signal bitshift_key2 : unsigned(63 downto 0);
signal xor_key2 : unsigned(63 downto 0);
signal mult_key2 : unsigned(127 downto 0);

signal key3 : unsigned(63 downto 0);
signal bitshift_key3 : unsigned(63 downto 0);
signal xor_key3 : unsigned(63 downto 0);
signal hash : std_logic_vector(31 downto 0);

begin

key1 <= unsigned(in_data);
bitshift_key1 <= shift_right(key1, 33);

key2 <= mult_key1(63 downto 0);
bitshift_key2 <= shift_right(key2, 33);

key3 <= mult_key2(63 downto 0);
bitshift_key3 <= shift_right(key3, 33);

hash <= std_logic_vector(xor_key3(31 downto 0));

out_valid <= requested5;
out_data <= hash;

process(clk)
begin
if clk'event and clk = '1' then
	if resetn = '0' then
		requested2 <= '0';
		requested3 <= '0';
		requested4 <= '0';
		requested5 <= '0';

		xor_key1 <= (others => '0');
		xor_key2 <= (others => '0');
		xor_key3 <= (others => '0');

		mult_key1 <= (others => '0');
		mult_key2 <= (others => '0');
	else
		xor_key1 <= key1 xor bitshift_key1;

		mult_key1 <= xor_key1*X"ff51afd7ed558ccd";
		
		xor_key2 <= key2 xor bitshift_key2;

		mult_key2 <= xor_key2*X"c4ceb9fe1a85ec53";

		xor_key3 <= key3 xor bitshift_key3;

		requested1 <= req_hash;
		requested2 <= requested1;
		requested3 <= requested2;
		requested4 <= requested3;
		requested5 <= requested4;
	end if;
end if;
end process;

end behavioral;