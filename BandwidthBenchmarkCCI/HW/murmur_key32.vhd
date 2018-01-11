library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity murmur_key32 is
generic (
	HASH_BITS : integer := 20);
port (
	clk : in std_logic;
	resetn : in std_logic;
	hash_select : in std_logic_vector(3 downto 0);
	req_hash : in std_logic;
	in_data : in std_logic_vector(63 downto 0);
	out_valid : out std_logic;
	out_data : out std_logic_vector(HASH_BITS + 63 downto 0));
end murmur_key32;

architecture behavioral of murmur_key32 is

signal requested1 : std_logic;
signal requested2 : std_logic;
signal requested3 : std_logic;
signal requested4 : std_logic;
signal requested5 : std_logic;

signal org_key1 : std_logic_vector(31 downto 0);
signal org_key2 : std_logic_vector(31 downto 0);
signal org_key3 : std_logic_vector(31 downto 0);
signal org_key4 : std_logic_vector(31 downto 0);
signal org_key5 : std_logic_vector(31 downto 0);

signal org_payload1 : std_logic_vector(31 downto 0);
signal org_payload2 : std_logic_vector(31 downto 0);
signal org_payload3 : std_logic_vector(31 downto 0);
signal org_payload4 : std_logic_vector(31 downto 0);
signal org_payload5 : std_logic_vector(31 downto 0);

signal key1 : unsigned(31 downto 0);
signal bitshift_key1 : unsigned(31 downto 0);
signal xor_key1 : unsigned(31 downto 0);
signal mult_key1 : unsigned(63 downto 0);

signal key2 : unsigned(31 downto 0);
signal bitshift_key2 : unsigned(31 downto 0);
signal xor_key2 : unsigned(31 downto 0);
signal mult_key2 : unsigned(63 downto 0);

signal key3 : unsigned(31 downto 0);
signal bitshift_key3 : unsigned(31 downto 0);
signal xor_key3 : unsigned(31 downto 0);
signal hash : std_logic_vector(HASH_BITS-1 downto 0);

signal internal_hash_select : std_logic_vector(3 downto 0);

begin

key1 <= unsigned(in_data(31 downto 0));
bitshift_key1 <= shift_right(key1, 16);

key2 <= mult_key1(31 downto 0);
bitshift_key2 <= shift_right(key2, 13);

key3 <= mult_key2(31 downto 0);
bitshift_key3 <= shift_right(key3, 16);

hash <= std_logic_vector(xor_key3(HASH_BITS-1 downto 0));

out_valid <= requested5;
out_data <= hash & org_payload5 & org_key5 when internal_hash_select = X"0" else
			org_key5(HASH_BITS-1 downto 0) & org_payload5 & org_key5;

process(clk)
begin
if clk'event and clk = '1' then
	internal_hash_select <= hash_select;
	if resetn = '0' then
		requested1 <= '0';
		requested2 <= '0';
		requested3 <= '0';
		requested4 <= '0';
		requested5 <= '0';
	else
		xor_key1 <= key1 xor bitshift_key1;

		mult_key1 <= xor_key1*X"85ebca6b";
		
		xor_key2 <= key2 xor bitshift_key2;

		mult_key2 <= xor_key2*X"c2b2ae35";

		xor_key3 <= key3 xor bitshift_key3;

		requested1 <= req_hash;
		requested2 <= requested1;
		requested3 <= requested2;
		requested4 <= requested3;
		requested5 <= requested4;

		org_key1 <= in_data(31 downto 0);
		org_key2 <= org_key1;
		org_key3 <= org_key2;
		org_key4 <= org_key3;
		org_key5 <= org_key4;

		org_payload1 <= in_data(63 downto 32);
		org_payload2 <= org_payload1;
		org_payload3 <= org_payload2;
		org_payload4 <= org_payload3;
		org_payload5 <= org_payload4;
	end if;
end if;
end process;

end behavioral;