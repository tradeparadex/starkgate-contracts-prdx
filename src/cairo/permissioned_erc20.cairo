#[starknet::contract]
mod PermissionedERC20 {
    use integer::BoundedInt;
    use zeroable::Zeroable;
    use starknet::{
        ContractAddress, get_caller_address, contract_address::ContractAddressZeroable,
        contract_address_const
    };
    use super::super::{
        erc20_interface::IERC20, erc20_interface::IERC20CamelOnly,
        mintable_token_interface::IMintableToken
    };


    #[storage]
    struct Storage {
        ERC20_name: felt252,
        ERC20_symbol: felt252,
        ERC20_decimals: u8,
        ERC20_total_supply: u256,
        ERC20_balances: LegacyMap<ContractAddress, u256>,
        ERC20_allowances: LegacyMap<(ContractAddress, ContractAddress), u256>,
        permitted_minter: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        value: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        owner: ContractAddress,
        spender: ContractAddress,
        value: u256
    }

    #[generate_trait]
    impl InternalFunctions of IInternalFunctions {
        fn _initializer(ref self: ContractState, name: felt252, symbol: felt252, decimals: u8) {
            self.ERC20_name.write(name);
            self.ERC20_symbol.write(symbol);
            self.ERC20_decimals.write(decimals);
        }

        // Mintable token internal functions.

        fn _mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            assert(recipient.is_non_zero(), 'ERC20: mint to 0');
            self.ERC20_total_supply.write(self.ERC20_total_supply.read() + amount);
            self.ERC20_balances.write(recipient, self.ERC20_balances.read(recipient) + amount);
            self
                .emit(
                    Event::Transfer(
                        Transfer {
                            from: contract_address_const::<0>(), to: recipient, value: amount
                        }
                    )
                );
        }

        fn _burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            assert(!account.is_zero(), 'ERC20: burn from 0');
            self.ERC20_total_supply.write(self.ERC20_total_supply.read() - amount);
            self.ERC20_balances.write(account, self.ERC20_balances.read(account) - amount);
            self
                .emit(
                    Event::Transfer(
                        Transfer { from: account, to: contract_address_const::<0>(), value: amount }
                    )
                );
        }

        // ERC20 internal functions.

        fn _increase_allowance(
            ref self: ContractState, spender: ContractAddress, added_value: u256
        ) -> bool {
            let caller = get_caller_address();
            self
                ._approve(
                    caller, spender, self.ERC20_allowances.read((caller, spender)) + added_value
                );
            true
        }

        fn _decrease_allowance(
            ref self: ContractState, spender: ContractAddress, subtracted_value: u256
        ) -> bool {
            let caller = get_caller_address();
            self
                ._approve(
                    caller,
                    spender,
                    self.ERC20_allowances.read((caller, spender)) - subtracted_value
                );
            true
        }

        fn _approve(
            ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256
        ) {
            assert(!owner.is_zero(), 'ERC20: approve from 0');
            assert(!spender.is_zero(), 'ERC20: approve to 0');
            self.ERC20_allowances.write((owner, spender), amount);
            self.emit(Event::Approval(Approval { owner: owner, spender: spender, value: amount }));
        }

        fn _transfer(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            assert(!sender.is_zero(), 'ERC20: transfer from 0');
            assert(!recipient.is_zero(), 'ERC20: transfer to 0');
            self.ERC20_balances.write(sender, self.ERC20_balances.read(sender) - amount);
            self.ERC20_balances.write(recipient, self.ERC20_balances.read(recipient) + amount);
            self.emit(Event::Transfer(Transfer { from: sender, to: recipient, value: amount }));
        }

        fn _spend_allowance(
            ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256
        ) {
            let current_allowance = self.ERC20_allowances.read((owner, spender));
            if current_allowance != BoundedInt::max() {
                self._approve(owner, spender, current_allowance - amount);
            }
        }
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        decimals: u8,
        initial_supply: u256,
        recipient: ContractAddress,
        permitted_minter: ContractAddress
    ) {
        self._initializer(name, symbol, decimals);
        self._mint(recipient, initial_supply);
        assert(permitted_minter.is_non_zero(), 'INVALID_MINTER_ADDRESS');
        self.permitted_minter.write(permitted_minter);
    }


    #[external(v0)]
    impl MintableToken of IMintableToken<ContractState> {
        fn permissioned_mint(ref self: ContractState, account: ContractAddress, amount: u256) {
            assert(get_caller_address() == self.permitted_minter.read(), 'MINTER_ONLY');
            self._mint(recipient: account, :amount);
        }
        fn permissioned_burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            assert(get_caller_address() == self.permitted_minter.read(), 'MINTER_ONLY');
            self._burn(:account, :amount);
        }
    }


    #[external(v0)]
    impl PermissionedERC20 of IERC20<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            self.ERC20_name.read()
        }

        fn symbol(self: @ContractState) -> felt252 {
            self.ERC20_symbol.read()
        }

        fn decimals(self: @ContractState) -> u8 {
            self.ERC20_decimals.read()
        }

        fn total_supply(self: @ContractState) -> u256 {
            self.ERC20_total_supply.read()
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.ERC20_balances.read(account)
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self.ERC20_allowances.read((owner, spender))
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let sender = get_caller_address();
            self._transfer(sender, recipient, amount);
            true
        }
        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let caller = get_caller_address();
            self._spend_allowance(sender, caller, amount);
            self._transfer(sender, recipient, amount);
            true
        }
        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            self._approve(caller, spender, amount);
            true
        }
        fn increase_allowance(
            ref self: ContractState, spender: ContractAddress, added_value: u256
        ) -> bool {
            self._increase_allowance(spender, added_value)
        }
        fn decrease_allowance(
            ref self: ContractState, spender: ContractAddress, subtracted_value: u256
        ) -> bool {
            self._decrease_allowance(spender, subtracted_value)
        }
    }

    #[external(v0)]
    impl ERC20CamelOnlyImpl of IERC20CamelOnly<ContractState> {
        fn totalSupply(self: @ContractState) -> u256 {
            PermissionedERC20::total_supply(self)
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            PermissionedERC20::balance_of(self, account)
        }

        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            PermissionedERC20::transfer_from(ref self, sender, recipient, amount)
        }
    }
}
