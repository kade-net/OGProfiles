/**
 This smart contract enables new users to kade to claim usernames
 and old users to onboard their profiles onto the new network
 It also enables these users to create nfts of their profiles
**/


module kade::OGProfilesNFTv1 {

    use std::option;
    use std::signer;
    use std::string;
    use std::string::String;
    use std::vector;
    use aptos_std::simple_map;
    use aptos_std::simple_map::SimpleMap;
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_std::string_utils;
    use aptos_framework::account;
    use aptos_framework::account::{SignerCapability};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::event::{EventHandle, emit_event};
    use aptos_framework::object;
    use aptos_framework::timestamp;
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    #[test_only]
    use aptos_std::debug;
    // use aptos_token_objects::token::royalty;

    // NFT Constants
    const COLLECTION_NAME: vector<u8> = b"Kade OG Profiles Collection";
    const COLLECTION_DESCRIPTION: vector<u8> = b"Collection of Kade's OG Profiles";
    const COLLECTION_URI: vector<u8> = b"https://kade.network";

    const EXPLORER_1_URI: vector<u8> = b"https://orange-urban-sloth-806.mypinata.cloud/ipfs/QmWcy4azPJ5KZEtpGeMBu3eCn3XxVeukD6Nos9EcZqyWRb?_gl=1*1m4yyd2*_ga*OTAyMjc0MDk2LjE3MDM1Nzk3MDE.*_ga_5RMPXG14TE*MTcwNTI5NDI1MS41LjEuMTcwNTI5NDI4MS4zMC4wLjA.";
    const EXPLORER_2_URI: vector<u8> = b"https://orange-urban-sloth-806.mypinata.cloud/ipfs/QmUYL6gALaNAFj3RpnfXvSHphJnagmFFEwTFCy8cRw9pgd?_gl=1*f334fl*_ga*OTAyMjc0MDk2LjE3MDM1Nzk3MDE.*_ga_5RMPXG14TE*MTcwNTI5NDI1MS41LjEuMTcwNTI5NDI4MS4zMC4wLjA.";
    const PIOONER_1_URI: vector<u8> = b"https://orange-urban-sloth-806.mypinata.cloud/ipfs/Qmc7x9HedC2qbwqpYyVELw7ceMdnPqbvdjH5neqchZwnYV?_gl=1*f334fl*_ga*OTAyMjc0MDk2LjE3MDM1Nzk3MDE.*_ga_5RMPXG14TE*MTcwNTI5NDI1MS41LjEuMTcwNTI5NDI4MS4zMC4wLjA.";
    const PIOONER_2_URI: vector<u8> = b"https://orange-urban-sloth-806.mypinata.cloud/ipfs/Qmaw8phxUiCeEUkhDBTztxDtV9TXwzYEdNiRY7oiBjodVV?_gl=1*mv0e7f*_ga*OTAyMjc0MDk2LjE3MDM1Nzk3MDE.*_ga_5RMPXG14TE*MTcwNTI5NDI1MS41LjEuMTcwNTI5NDI4MS4zMC4wLjA.";

    // seed for the module's resource account
    const SEED: vector<u8> = b"kade og profiles v1";

    // Error codes
    const EUserNameExists: u64 = 1;
    const EAddressDoesNotExist: u64 = 2;
    const EProfileDoesNotExist: u64 = 3;
    const EVariantDoesNotExist: u64 = 4;
    const EOperationNotPermitted: u64 = 5;


    struct Profile has key {
        name: String,
        variant: u64,
        uri: String,
    }

    struct Friends has store, copy, drop {
        count: u64,
        friends: vector<address>,
    }

    struct State has key {
        claimed_usernames: SimpleMap<address,string::String>,
        minted_nfts: SimpleMap<address, address>,
        signer_capability: SignerCapability,
        claim_username_event: EventHandle<ClaimUsernameEvent>,
        collection_address: address,
        minted_profiles: u64,
        profile_mint_event: EventHandle<ProfileMintEvent>,
        referral_event: EventHandle<ReffaralEvent>,
        friend_map: SimpleMap<address, Friends>,
    }

    struct PatchState has key {
        claimed_usernames: SmartTable<string::String, address>,
        minted_nfts: SmartTable<address, address>,
        friend_map: SmartTable<address, Friends>,
        existing_accounts: vector<address>
    }

    struct ReffaralEvent has store, drop {
        referrer: address, // the user who referred
        referee: address, // the user who was referred
        timestamp_seconds: u64,
    }

    struct ClaimUsernameEvent has store, drop {
        owner: address,
        username: string::String,
        timestamp_seconds: u64,
    }

    struct ProfileMintEvent has store, drop {
        // address of the user
        owner: address,
        // address of the nft
        profile_address: address,
        // timestamp
        timestamp_seconds: u64,
    }

    /**
        Initialize the module by setting up the resource account with the SEED constant
        registering the resource account with the AptosCoin
        creating and moving the State resource to the resource account
        @param admin - signer representing the admin
    **/
    fun init_module(admin: &signer) {
        let (resource_signer, signer_capability) = account::create_resource_account(admin, SEED);
        coin::register<AptosCoin>(&resource_signer);

        collection::create_unlimited_collection(
            &resource_signer,
            string::utf8(COLLECTION_DESCRIPTION),
            string::utf8(COLLECTION_NAME),
            option::none(),
            string::utf8(COLLECTION_URI)
        );

        let collection_address = collection::create_collection_address(&signer::address_of(&resource_signer), &string::utf8(COLLECTION_NAME));

        let state = State {
            signer_capability,
            claim_username_event: account::new_event_handle<ClaimUsernameEvent>(&resource_signer),
            claimed_usernames: simple_map::new(),
            collection_address,
            profile_mint_event: account::new_event_handle<ProfileMintEvent>(&resource_signer),
            minted_profiles: 0,
            minted_nfts: simple_map::new(),
            referral_event: account::new_event_handle<ReffaralEvent>(&resource_signer),
            friend_map: simple_map::new(),
        };

        move_to(&resource_signer, state)
    }

    public entry fun claim_username(
        claimer: &signer,
        username: String,
    ) acquires State {
        let resource_address = account::create_resource_address(&@kade, SEED);


        let state = borrow_global_mut<State>(resource_address);
        assert_username_unclaimed(username, &state.claimed_usernames);


        simple_map::add(&mut state.claimed_usernames, signer::address_of(claimer), username);


        simple_map::add(&mut state.friend_map, signer::address_of(claimer), Friends{
            count: 0,
            friends: vector::empty(),
        });

        event::emit_event(&mut state.claim_username_event, ClaimUsernameEvent{
            username,
            owner: signer::address_of(claimer),
            timestamp_seconds: timestamp::now_seconds(),
        });
    }

    public entry fun claim_username_reffered(
        claimer: &signer,
        username: String,
        referrer:address,
    ) acquires State {
        assert!(signer::address_of(claimer) != referrer, EOperationNotPermitted);
        let resource_address = account::create_resource_address(&@kade, SEED);


        let state = borrow_global_mut<State>(resource_address);
        assert_username_unclaimed(username, &state.claimed_usernames);


        simple_map::add(&mut state.claimed_usernames, signer::address_of(claimer), username);


        simple_map::add(&mut state.friend_map, signer::address_of(claimer), Friends{
            count: 0,
            friends: vector::empty(),
        });



            assert!(simple_map::contains_key(&state.claimed_usernames, &referrer), EAddressDoesNotExist);
            let friends = simple_map::borrow_mut(&mut state.friend_map, &referrer);

            friends.count = friends.count + 1;
            vector::push_back(&mut friends.friends, signer::address_of(claimer));

            event::emit_event(&mut state.referral_event, ReffaralEvent{
                referrer,
                referee: signer::address_of(claimer),
                timestamp_seconds: timestamp::now_seconds(),
            });


        event::emit_event(&mut state.claim_username_event, ClaimUsernameEvent{
            username,
            owner: signer::address_of(claimer),
            timestamp_seconds: timestamp::now_seconds(),
        });
    }

    // let kade cover the gas cost of claiming a username
    public entry fun free_claim_username(kade_account: &signer, claimer_address: address, username: String) acquires State {
        assert!(signer::address_of(kade_account) == @kade, EOperationNotPermitted);
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global_mut<State>(resource_address);
        assert_username_unclaimed(username, &state.claimed_usernames);
        simple_map::add(&mut state.claimed_usernames, claimer_address, username);

        simple_map::add(&mut state.friend_map, claimer_address, Friends{
            count: 0,
            friends: vector::empty(),
        });

        event::emit_event(&mut state.claim_username_event, ClaimUsernameEvent{
            username,
            owner: claimer_address,
            timestamp_seconds: timestamp::now_seconds(),
        });
    }


    public entry fun free_claim_username_reffered(kade_account: &signer, claimer_address: address, username: String, referrer: address) acquires State {
        assert!(signer::address_of(kade_account) == @kade, EOperationNotPermitted);
        assert!(claimer_address != referrer, EOperationNotPermitted);
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global_mut<State>(resource_address);
        assert_username_unclaimed(username, &state.claimed_usernames);
        simple_map::add(&mut state.claimed_usernames, claimer_address, username);

        simple_map::add(&mut state.friend_map, claimer_address, Friends{
            count: 0,
            friends: vector::empty(),
        });

            assert!(simple_map::contains_key(&state.claimed_usernames, &referrer), EAddressDoesNotExist);
            let friends = simple_map::borrow_mut(&mut state.friend_map, &referrer);

            friends.count = friends.count + 1;
            vector::push_back(&mut friends.friends, claimer_address);

            event::emit_event(&mut state.referral_event, ReffaralEvent{
                referrer,
                referee: claimer_address,
                timestamp_seconds: timestamp::now_seconds(),
            });




        event::emit_event(&mut state.claim_username_event, ClaimUsernameEvent{
            username,
            owner: claimer_address,
            timestamp_seconds: timestamp::now_seconds(),
        });
    }

    // user who has already claimed a username can claim a profile nft
    public entry fun mint_profile_nft(claimer: &signer, variant: u64) acquires State {
        assert!(!has_profile_nft(signer::address_of(claimer)), EOperationNotPermitted);
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global_mut<State>(resource_address);
        let resource_signer = account::create_signer_with_capability(&state.signer_capability);
        let username = *simple_map::borrow(&state.claimed_usernames, &signer::address_of(claimer));
        let count = string_utils::to_string(&state.minted_profiles);
        state.minted_profiles = state.minted_profiles + 1;
        let profile_nft_uri = string::utf8(b"");

        if(variant == 1) {
            profile_nft_uri = string::utf8(EXPLORER_1_URI);
        } else if(variant == 2) {
            profile_nft_uri = string::utf8(EXPLORER_2_URI);
        } else if(variant == 3) {
            profile_nft_uri = string::utf8(PIOONER_1_URI);
        } else if(variant == 4) {
            profile_nft_uri = string::utf8(PIOONER_2_URI);
        };

        let profile_name = string_utils::format2(&b"Profile #{} : {}",count, username);

        let nft = token::create_named_token(
            &resource_signer,
            string::utf8(COLLECTION_NAME),
            string::utf8(b"PROFILE MINT"),
            profile_name,
            option::none(),
            profile_nft_uri,
        );



        let nft_address = object::address_from_constructor_ref(&nft);
        let nft_signer = object::generate_signer(&nft);

        simple_map::add(&mut state.minted_nfts, signer::address_of(claimer), nft_address);

        object::transfer_raw(&resource_signer, nft_address, signer::address_of(claimer));

        let profile = Profile {
            name:  profile_name,
            variant,
            uri: profile_nft_uri,
        };

        move_to<Profile>(&nft_signer, profile);

        emit_event(&mut state.profile_mint_event, ProfileMintEvent{
            timestamp_seconds: timestamp::now_seconds(),
            owner: signer::address_of(claimer),
            profile_address: nft_address,
        });

    }

    // let kade cover the gas cost of minting a profile nft
    public entry fun free_mint_profile_nft(kade_account: &signer, claimer_address: address, variant: u64) acquires State {
        assert!(signer::address_of(kade_account) == @kade, EOperationNotPermitted);
        assert!(!has_profile_nft(claimer_address), EOperationNotPermitted);
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global_mut<State>(resource_address);
        let resource_signer = account::create_signer_with_capability(&state.signer_capability);
        let username = *simple_map::borrow(&state.claimed_usernames, &claimer_address);
        let count = string_utils::to_string(&state.minted_profiles);
        state.minted_profiles = state.minted_profiles + 1;
        let profile_nft_uri = string::utf8(b"");

        if(variant == 1) {
            profile_nft_uri = string::utf8(EXPLORER_1_URI);
        } else if(variant == 2) {
            profile_nft_uri = string::utf8(EXPLORER_2_URI);
        } else if(variant == 3) {
            profile_nft_uri = string::utf8(PIOONER_1_URI);
        } else if(variant == 4) {
            profile_nft_uri = string::utf8(PIOONER_2_URI);
        };

        let profile_name = string_utils::format2(&b"Profile #{} : {}",count, username);
        let description = string::utf8(b"KADE PIONEER");
        if(variant < 3) {
            description = string::utf8(b"KADE EXPLORER");
        };


        let nft = token::create_named_token(
            &resource_signer,
            string::utf8(COLLECTION_NAME),
            description,
            profile_name,
            option::none(),
            profile_nft_uri,
        );

        let nft_address = object::address_from_constructor_ref(&nft);
        let nft_signer = object::generate_signer(&nft);

        simple_map::add(&mut state.minted_nfts, claimer_address, nft_address);

        object::transfer_raw(&resource_signer, nft_address, claimer_address);

        let profile = Profile {
            name:  profile_name,
            variant,
            uri: profile_nft_uri,
        };

        move_to<Profile>(&nft_signer, profile);

        emit_event(&mut state.profile_mint_event, ProfileMintEvent{
            timestamp_seconds: timestamp::now_seconds(),
            owner: claimer_address,
            profile_address: nft_address,
        });

    }

    public entry fun patch_init_module(admin: &signer) acquires State {
        assert!(signer::address_of(admin) == @kade, EOperationNotPermitted);
        let resource_address = account::create_resource_address(&@kade, SEED);

        let existingState = borrow_global<State>(resource_address);
        let signer  = account::create_signer_with_capability(&existingState.signer_capability);

        let state = PatchState {
            claimed_usernames: smart_table::new(),
            minted_nfts: smart_table::new(),
            friend_map: smart_table::new(),
            existing_accounts: vector::empty(),
        };

        move_to(&signer, state);
    }

    public entry fun patch_claim_username(claimer: &signer, username: String) acquires PatchState, State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let patchState = borrow_global_mut<PatchState>(resource_address);
        let existingState = borrow_global_mut<State>(resource_address);

        assert_username_unclaimed(username, &existingState.claimed_usernames);
        patch_assert_username_unclaimed(username, &patchState.claimed_usernames);

        assert!(!vector::contains(&patchState.existing_accounts, &signer::address_of(claimer)), EOperationNotPermitted);


        smart_table::add(&mut patchState.claimed_usernames, username, signer::address_of(claimer));
        smart_table::add(&mut patchState.friend_map, signer::address_of(claimer), Friends{
            count: 0,
            friends: vector::empty(),
        });

        vector::push_back(&mut patchState.existing_accounts, signer::address_of(claimer));

        event::emit_event(&mut existingState.claim_username_event, ClaimUsernameEvent {
            username,
            owner: signer::address_of(claimer),
            timestamp_seconds: timestamp::now_seconds(),
        });
    }

    public entry  fun patch_claim_username_reffered(claimer: &signer, username: String, refferer: address, ) acquires PatchState, State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let patchState = borrow_global_mut<PatchState>(resource_address);
        let existingState = borrow_global_mut<State>(resource_address);

        assert_username_unclaimed(username, &existingState.claimed_usernames);
        patch_assert_username_unclaimed(username, &patchState.claimed_usernames);

        assert!(!vector::contains(&patchState.existing_accounts, &signer::address_of(claimer)), EOperationNotPermitted);
        assert!(vector::contains(&patchState.existing_accounts, &refferer), EOperationNotPermitted);

        smart_table::add(&mut patchState.claimed_usernames, username, signer::address_of(claimer));
        smart_table::add(&mut patchState.friend_map, signer::address_of(claimer), Friends{
            count: 0,
            friends: vector::empty(),
        });
        vector::push_back(&mut patchState.existing_accounts, signer::address_of(claimer));

        assert!(smart_table::contains(&patchState.claimed_usernames, username), EAddressDoesNotExist);
        let friends = smart_table::borrow_mut(&mut patchState.friend_map, refferer);

        friends.count = friends.count + 1;
        vector::push_back(&mut friends.friends, signer::address_of(claimer));

        event::emit_event(&mut existingState.referral_event, ReffaralEvent{
            referrer: refferer,
            referee: signer::address_of(claimer),
            timestamp_seconds: timestamp::now_seconds(),
        });

        event::emit_event(&mut existingState.claim_username_event, ClaimUsernameEvent {
            username,
            owner: signer::address_of(claimer),
            timestamp_seconds: timestamp::now_seconds(),
        });
    }
    public entry fun patch_mint_profile_nft(claimer: &signer, claimerUsername: String, variant: u64) acquires PatchState, State {
        assert!(!patch_has_profile_nft(signer::address_of(claimer)), EOperationNotPermitted);
        let resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global_mut<State>(resource_address);
        let patchState = borrow_global_mut<PatchState>(resource_address);

        assert!(vector::contains(&patchState.existing_accounts, &signer::address_of(claimer)), EOperationNotPermitted);
        assert!(smart_table::contains(&patchState.claimed_usernames, claimerUsername), EAddressDoesNotExist);

        let storedAddress = *smart_table::borrow(&patchState.claimed_usernames, claimerUsername);
        assert!(storedAddress == signer::address_of(claimer), EOperationNotPermitted);

        let resource_signer = account::create_signer_with_capability(&state.signer_capability);
        let username = claimerUsername;
        let count = string_utils::to_string(&state.minted_profiles);
        state.minted_profiles = state.minted_profiles + 1;
        let profile_nft_uri = string::utf8(b"");

        if(variant == 1) {
            profile_nft_uri = string::utf8(EXPLORER_1_URI);
        } else if(variant == 2) {
            profile_nft_uri = string::utf8(EXPLORER_2_URI);
        } else if(variant == 3) {
            profile_nft_uri = string::utf8(PIOONER_1_URI);
        } else if(variant == 4) {
            profile_nft_uri = string::utf8(PIOONER_2_URI);
        };

        let profile_name = string_utils::format2(&b"Profile #{} : {}",count, username);

        let nft = token::create_named_token(
            &resource_signer,
            string::utf8(COLLECTION_NAME),
            string::utf8(b"PROFILE MINT"),
            profile_name,
            option::none(),
            profile_nft_uri,
        );



        let nft_address = object::address_from_constructor_ref(&nft);
        let nft_signer = object::generate_signer(&nft);

        smart_table::add(&mut patchState.minted_nfts, signer::address_of(claimer), nft_address);

        object::transfer_raw(&resource_signer, nft_address, signer::address_of(claimer));

        let profile = Profile {
            name:  profile_name,
            variant,
            uri: profile_nft_uri,
        };

        move_to<Profile>(&nft_signer, profile);

        emit_event(&mut state.profile_mint_event, ProfileMintEvent{
            timestamp_seconds: timestamp::now_seconds(),
            owner: signer::address_of(claimer),
            profile_address: nft_address,
        });
    }

    inline fun patch_assert_username_unclaimed(username: String, claimed: &SmartTable<String, address>)  {
        let has_been_claimed = smart_table::contains(claimed, username);
        assert!(!has_been_claimed, EUserNameExists);
    }

    inline fun assert_username_unclaimed(username: String, claimed: &SimpleMap<address,String>) {

        let values = simple_map::values(claimed);
        assert!(!vector::contains(&values, &username), EUserNameExists);
    }

    inline fun assert_user_does_not_have_profile_nft(claimer_address: address, minted_nfts: &SimpleMap<address, address>) {
        assert!(!simple_map::contains_key(minted_nfts, &claimer_address), EOperationNotPermitted);
    }


    // View all claimed usernames

    #[view]
    public fun get_claimed_usernames() : SimpleMap<address,String> acquires  State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global<State>(resource_address);
        state.claimed_usernames
    }

    // View single username
    #[view]
    public fun get_claimed_username(claimer_address: address): String acquires  State {

        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global<State>(resource_address);
        // check if address exists
        assert!(simple_map::contains_key(&state.claimed_usernames, &claimer_address), EAddressDoesNotExist);
        let username = simple_map::borrow(&state.claimed_usernames, &claimer_address);
        *username
    }

    #[view]
    public fun patch_get_claimed_username(claimer_address: address): string::String acquires  State, PatchState {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global<State>(resource_address);
        let patchState = borrow_global<PatchState>(resource_address);
        // check if address exists

        let claimer_username = string::utf8(b"");

        let exists = smart_table::any(&patchState.claimed_usernames, |_username, _address| {
            let username: &string::String = _username;
            let address: &address = _address;
            if(*address == claimer_address){
                claimer_username = *username;
                true
            }else{
                false
            }
        });

        if(exists) {
            return claimer_username
        };

        let username = simple_map::borrow(&state.claimed_usernames, &claimer_address);

        *username
    }

    // Check if a username has already been claimed
    #[view]
    public fun is_username_claimed(username: String): bool acquires  State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global<State>(resource_address);
        let values = simple_map::values(&state.claimed_usernames);
        vector::contains(&values, &username)
    }

    #[view]
    public fun patch_is_username_claimed(username: String): bool acquires PatchState, State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let patchState = borrow_global<PatchState>(resource_address);
        let existingState = borrow_global<State>(resource_address);

        let values = simple_map::values(&existingState.claimed_usernames);

        if(vector::contains(&values, &username)){
            return true
        };

        smart_table::contains(&patchState.claimed_usernames, username)
    }

    // Check if a user already has a profile nft
    #[view]
    public fun has_profile_nft(claimer_address: address): bool acquires  State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global<State>(resource_address);

        // check if address exists
        if(!simple_map::contains_key(&state.minted_nfts, &claimer_address)){
            return false
        };

        let nft_address = *simple_map::borrow(&state.minted_nfts, &claimer_address);
        exists<Profile>(nft_address)
    }

    #[view]
    public fun patch_has_profile_nft(claimer_address: address): bool acquires  State, PatchState {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global<State>(resource_address);
        let patchState = borrow_global<PatchState>(resource_address);
        if(!smart_table::contains(&patchState.minted_nfts, claimer_address)){
            return false
        }else if(!simple_map::contains_key(&state.minted_nfts, &claimer_address)){
            return false
        }else if(smart_table::contains(&patchState.minted_nfts, claimer_address)){
            let nft_address = *smart_table::borrow(&patchState.minted_nfts, claimer_address);
            let e = exists<Profile>(nft_address);
            return e
        }else if(simple_map::contains_key(&state.minted_nfts, &claimer_address)){
            let nft_address = *simple_map::borrow(&state.minted_nfts, &claimer_address);
            exists<Profile>(nft_address)
        } else {
            return false
        }
    }

    // Get the user's profile nft
    #[view]
    public fun get_profile_nft(claimer_address: address): (String, u64, String) acquires Profile, State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global<State>(resource_address);
        // check if address exists
        assert!(simple_map::contains_key(&state.minted_nfts, &claimer_address), EAddressDoesNotExist);
        let nft_address = *simple_map::borrow(&state.minted_nfts, &claimer_address);
        let profile = borrow_global<Profile>(nft_address);
        (profile.name, profile.variant, profile.uri)
    }

    #[view]
    public fun patch_get_profile_nft(claimer_address: address): (String, u64, String) acquires Profile, State, PatchState {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global<State>(resource_address);
        let patchState = borrow_global<PatchState>(resource_address);
        // check if address exists
        if(smart_table::contains(&patchState.minted_nfts, claimer_address)){
            let nft_address = *smart_table::borrow(&patchState.minted_nfts, claimer_address);
            let profile = borrow_global<Profile>(nft_address);
            return (profile.name, profile.variant, profile.uri)
        };
        if(simple_map::contains_key(&state.minted_nfts, &claimer_address)){
            let nft_address = *simple_map::borrow(&state.minted_nfts, &claimer_address);
            let profile = borrow_global<Profile>(nft_address);
            return (profile.name, profile.variant, profile.uri)
        };
        (string::utf8(b""), 0, string::utf8(b""))
    }

    // Check if a user already exists
    #[view]
    public fun user_exists(claimer_address: address): bool acquires  State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global<State>(resource_address);
        // check if address exists
        simple_map::contains_key(&state.claimed_usernames, &claimer_address)
    }

    #[view]
    public fun patch_user_exists(claimer_address: address): bool acquires  PatchState, State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let patchState = borrow_global<PatchState>(resource_address);
        let existingState = borrow_global<State>(resource_address);
        // check if address exists
        if(vector::contains(&patchState.existing_accounts, &claimer_address)){
            return true
        };
        simple_map::contains_key(&existingState.claimed_usernames, &claimer_address)
    }


    // TESTS
    #[test(admin = @kade)]
    fun test_init_module_success(admin: &signer) acquires State {
        let admin_address = signer::address_of(admin);
        account::create_account_for_test(admin_address);

        init_module(admin);

        let expected_resource_account_address = account::create_resource_address(&admin_address, SEED);

        assert!(coin::is_account_registered<AptosCoin>(expected_resource_account_address), 4);

        assert!(exists<State>(expected_resource_account_address), 0);

        let state = borrow_global<State>(expected_resource_account_address);
        let claim_username_events = event::counter(&state.claim_username_event);

        assert!(claim_username_events == 0, 5);
        assert!(simple_map::length(&state.claimed_usernames) == 0, 6);
        assert!(account::get_signer_capability_address(&state.signer_capability) == expected_resource_account_address, 7);
    }

    #[test(admin = @kade, user = @0xCED, aptos_framework = @aptos_framework)]
    fun test_claim_username_success(admin: &signer, user: &signer, aptos_framework: &signer) acquires State {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let aptos_framework_address = signer::address_of(aptos_framework);
        let resource_address = account::create_resource_address(&@kade, SEED);

        let aptos =account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);

        let username_to_claim = string::utf8(b"kade");

        claim_username(user, username_to_claim);

        let state = borrow_global<State>(resource_address);

        let claim_events_count = event::counter(&state.claim_username_event);

        assert!(claim_events_count == 1, 7);

        assert!(simple_map::contains_key(&state.claimed_usernames, &user_address), 8);

        assert!(simple_map::borrow(&state.claimed_usernames, &user_address) == &username_to_claim, 9);
    }



    #[test(admin = @kade, user = @0xCED, user2 = @0xCEE, aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = EUserNameExists, location = Self)]
    fun test_claim_username_fails_if_exists(admin: &signer, user: &signer, user2: &signer, aptos_framework: &signer) acquires State {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let user2_address = signer::address_of(user2);
        let aptos_framework_address = signer::address_of(aptos_framework);

        let aptos =account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);
        account::create_account_for_test(user2_address);

        init_module(admin);

        let username_to_claim = string::utf8(b"kade");

        claim_username(user, username_to_claim);

        claim_username(user2, username_to_claim)
    }

    #[test(admin = @kade, user = @0xCED, aptos_framework = @aptos_framework)]
    fun test_mint_profile_nft_success(admin: &signer, user: &signer, aptos_framework: &signer) acquires State, Profile {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let aptos_framework_address = signer::address_of(aptos_framework);
        let resource_address = account::create_resource_address(&@kade, SEED);

        let aptos =account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);

        let username_to_claim = string::utf8(b"kade");

        claim_username(user, username_to_claim);

        mint_profile_nft(user, 1);

        let state = borrow_global<State>(resource_address);

        let mint_events_count = event::counter(&state.profile_mint_event);

        assert!(mint_events_count == 1, 7);

        assert!(simple_map::contains_key(&state.minted_nfts, &user_address), 8);

        let nft_address = *simple_map::borrow(&state.minted_nfts, &user_address);

        assert!(exists<Profile>(nft_address), 9);

        let profile = borrow_global<Profile>(nft_address);
        let expected_profile_name = string_utils::format2(&b"Profile #{} : {}",string_utils::to_string(&0), username_to_claim);
        debug::print<String>(&expected_profile_name);
        debug::print<Profile>(profile);

        assert!(profile.name == expected_profile_name, 10);
    }

    // test username is claimed checker
    #[test(admin = @kade, user = @0xCED, aptos_framework = @aptos_framework)]
    fun test_is_username_claimed_success(admin: &signer, user: &signer, aptos_framework: &signer) acquires State {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let aptos_framework_address = signer::address_of(aptos_framework);

        let aptos =account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);

        let username_to_claim = string::utf8(b"kade");

        claim_username(user, username_to_claim);

        let is_claimed = is_username_claimed(username_to_claim);

        assert!(is_claimed == true, 7);
    }

    // test username is claimed checker
    #[test(admin = @kade, user = @0xCED, aptos_framework = @aptos_framework)]
    fun test_is_username_claimed_fails(admin: &signer, user: &signer, aptos_framework: &signer) acquires State {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let aptos_framework_address = signer::address_of(aptos_framework);

        let aptos =account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);

        let username_to_claim = string::utf8(b"kade");

        claim_username(user, username_to_claim);

        let is_claimed = is_username_claimed(string::utf8(b"not kade"));

        assert!(is_claimed == false, 7);
    }

    // test nft minted by user checker
    #[test(admin = @kade, user = @0xCED, aptos_framework = @aptos_framework)]
    fun test_has_profile_nft_success(admin: &signer, user: &signer, aptos_framework: &signer) acquires State {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let aptos_framework_address = signer::address_of(aptos_framework);

        let aptos =account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);

        let username_to_claim = string::utf8(b"kade");

        claim_username(user, username_to_claim);

        mint_profile_nft(user, 1);

        let has_nft = has_profile_nft(user_address);

        assert!(has_nft == true, 7);
    }

    // test nft profile checker
    #[test(admin = @kade, user = @0xCED, aptos_framework = @aptos_framework)]
    fun test_get_profile_nft_success(admin: &signer, user: &signer, aptos_framework: &signer) acquires State, Profile {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let aptos_framework_address = signer::address_of(aptos_framework);

        let aptos =account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);

        let username_to_claim = string::utf8(b"kade");

        claim_username(user, username_to_claim);

        mint_profile_nft(user, 1);

        let (profile_name, variant, uri) = get_profile_nft(user_address);

        let expected_profile_name = string_utils::format2(&b"Profile #{} : {}",string_utils::to_string(&0), username_to_claim);

        assert!(profile_name == expected_profile_name, 7);
        assert!(variant == 1, 8);
        assert!(uri == string::utf8(EXPLORER_1_URI), 9);
    }

    // test claim username can be done by kade on behalf of a user
    #[test(admin = @kade, user = @0xCED, aptos_framework = @aptos_framework)]
    fun test_free_claim_username_success(admin: &signer, user: &signer, aptos_framework: &signer) acquires State {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let aptos_framework_address = signer::address_of(aptos_framework);
        let resource_address = account::create_resource_address(&@kade, SEED);

        let aptos =account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);

        let username_to_claim = string::utf8(b"kade");

        free_claim_username(admin, user_address, username_to_claim);

        let state = borrow_global<State>(resource_address);

        let claim_events_count = event::counter(&state.claim_username_event);

        assert!(claim_events_count == 1, 7);

        assert!(simple_map::contains_key(&state.claimed_usernames, &user_address), 8);

        assert!(simple_map::borrow(&state.claimed_usernames, &user_address) == &username_to_claim, 9);
    }


    // test mint profile nft can be done by kade on behalf of a user
    #[test(admin = @kade, user = @0xCED, aptos_framework = @aptos_framework)]
    fun test_free_mint_profile_nft_success(admin: &signer, user: &signer, aptos_framework: &signer) acquires State, Profile {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let aptos_framework_address = signer::address_of(aptos_framework);
        let resource_address = account::create_resource_address(&@kade, SEED);

        let aptos =account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);

        let username_to_claim = string::utf8(b"kade");

        free_claim_username(admin, user_address, username_to_claim);

        free_mint_profile_nft(admin, user_address, 1);

        let state = borrow_global<State>(resource_address);

        let mint_events_count = event::counter(&state.profile_mint_event);

        assert!(mint_events_count == 1, 7);

        assert!(simple_map::contains_key(&state.minted_nfts, &user_address), 8);

        let nft_address = *simple_map::borrow(&state.minted_nfts, &user_address);

        assert!(exists<Profile>(nft_address), 9);

        let profile = borrow_global<Profile>(nft_address);
        let expected_profile_name = string_utils::format2(&b"Profile #{} : {}",string_utils::to_string(&0), username_to_claim);
        debug::print<String>(&expected_profile_name);
        debug::print<Profile>(profile);

        assert!(profile.name == expected_profile_name, 10);
    }


    // test claim username reffered
    #[test(admin = @kade, user = @0xCED, user2 = @0xCEE, aptos_framework = @aptos_framework)]
    fun test_claim_username_reffered_success(admin: &signer, user: &signer, user2: &signer, aptos_framework: &signer) acquires State {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let user2_address = signer::address_of(user2);
        let aptos_framework_address = signer::address_of(aptos_framework);
        let resource_address = account::create_resource_address(&@kade, SEED);

        let aptos =account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);
        account::create_account_for_test(user2_address);

        init_module(admin);

        let username_to_claim = string::utf8(b"kade");
        let second_username_to_claim = string::utf8(b"not kade");
        claim_username(user, username_to_claim);

        claim_username_reffered(user2, second_username_to_claim, user_address);

        let state = borrow_global<State>(resource_address);

        let claim_events_count = event::counter(&state.claim_username_event);

        assert!(claim_events_count == 2, 7);

        assert!(simple_map::contains_key(&state.claimed_usernames, &user2_address), 8);

        assert!(simple_map::borrow(&state.claimed_usernames, &user2_address) == &second_username_to_claim, 9);

        assert!(simple_map::contains_key(&state.friend_map, &user_address), 10);

        let friends = simple_map::borrow(&state.friend_map, &user_address);

        assert!(friends.count == 1, 11);

        assert!(vector::length(&friends.friends) == 1, 12);

        assert!(*vector::borrow(&friends.friends, 0) == user2_address, 13);

    }

    // test free claim username reffered success
    #[test(admin = @kade, user = @0xCED, user2 = @0xCEE, aptos_framework = @aptos_framework)]
    fun test_free_claim_username_reffered_success(admin: &signer, user: &signer, user2: &signer, aptos_framework: &signer) acquires State {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let user2_address = signer::address_of(user2);
        let aptos_framework_address = signer::address_of(aptos_framework);
        let resource_address = account::create_resource_address(&@kade, SEED);

        let aptos =account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);
        account::create_account_for_test(user2_address);

        init_module(admin);

        let username_to_claim = string::utf8(b"kade");
        let second_username_to_claim = string::utf8(b"not kade");
        claim_username(user, username_to_claim);

        free_claim_username_reffered(admin, user2_address, second_username_to_claim, user_address);

        let state = borrow_global<State>(resource_address);

        let claim_events_count = event::counter(&state.claim_username_event);

        assert!(claim_events_count == 2, 7);

        assert!(simple_map::contains_key(&state.claimed_usernames, &user2_address), 8);

        assert!(simple_map::borrow(&state.claimed_usernames, &user2_address) == &second_username_to_claim, 9);

        assert!(simple_map::contains_key(&state.friend_map, &user_address), 10);

        let friends = simple_map::borrow(&state.friend_map, &user_address);

        assert!(friends.count == 1, 11);

        assert!(vector::length(&friends.friends) == 1, 12);

        assert!(*vector::borrow(&friends.friends, 0) == user2_address, 13);

    }

    // test same user cannot refer themselves
    #[test(admin = @kade, user = @0xCED, aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = EOperationNotPermitted, location = Self)]
    fun test_claim_username_reffered_fails_if_same_user(admin: &signer, user: &signer, aptos_framework: &signer) acquires State {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let aptos_framework_address = signer::address_of(aptos_framework);

        let aptos =account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);

        claim_username_reffered(user, string::utf8(b"kade"), user_address);
    }

    // test free same user cannot refer themselves
    #[test(admin = @kade, user = @0xCED, aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = EOperationNotPermitted, location = Self)]
    fun test_free_claim_username_reffered_fails_if_same_user(admin: &signer, user: &signer, aptos_framework: &signer) acquires State {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let aptos_framework_address = signer::address_of(aptos_framework);

        let aptos =account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);

        free_claim_username_reffered(admin, user_address, string::utf8(b"kade"), user_address);
    }


    // ===
    // Patch tests
    // ===

    // test patch init module success
    #[test(admin = @kade)]
    fun test_patch_init_module_success(admin: &signer) acquires State {
        let admin_address = signer::address_of(admin);
        account::create_account_for_test(admin_address);

        init_module(admin);
        patch_init_module(admin);

        let expected_resource_account_address = account::create_resource_address(&admin_address, SEED);

        assert!(coin::is_account_registered<AptosCoin>(expected_resource_account_address), 4);

        assert!(exists<PatchState>(expected_resource_account_address), 0);

        let state = borrow_global<State>(expected_resource_account_address);
        let claim_username_events = event::counter(&state.claim_username_event);

        assert!(claim_username_events == 0, 5);
        assert!(simple_map::length(&state.claimed_usernames) == 0, 6);

        assert!(account::get_signer_capability_address(&state.signer_capability) == expected_resource_account_address, 7);
    }

    // test patch claim username success
    #[test(admin = @kade, user = @0xCED, aptos_framework = @aptos_framework)]
    fun test_patch_claim_username_success(admin: &signer, user: &signer, aptos_framework: &signer) acquires PatchState, State {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let aptos_framework_address = signer::address_of(aptos_framework);
        let resource_address = account::create_resource_address(&@kade, SEED);

        let aptos =account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);
        patch_init_module(admin);

        let username_to_claim = string::utf8(b"kade");

        patch_claim_username(user, username_to_claim);

        let state = borrow_global<State>(resource_address);
        let patchState = borrow_global<PatchState>(resource_address);

        assert!(*smart_table::borrow(&patchState.claimed_usernames, username_to_claim) == user_address, 7);

        assert!(vector::length(&patchState.existing_accounts) == 1, 8);

        let claim_events_count = event::counter(&state.claim_username_event);

        assert!(claim_events_count == 1, 9);



    }

    // test patch claim username reffered success

    #[test(admin = @kade, user = @0xCED, user2 = @0xCEE, aptos_framework = @aptos_framework)]
    fun test_patch_claim_username_reffered_success(admin: &signer, user: &signer, user2: &signer, aptos_framework: &signer) acquires PatchState, State {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let user2_address = signer::address_of(user2);
        let aptos_framework_address = signer::address_of(aptos_framework);
        let resource_address = account::create_resource_address(&@kade, SEED);

        let aptos =account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);
        account::create_account_for_test(user2_address);

        init_module(admin);
        patch_init_module(admin);

        let username_to_claim = string::utf8(b"kade");
        let second_username_to_claim = string::utf8(b"not kade");
        patch_claim_username(user, username_to_claim);

        patch_claim_username_reffered(user2, second_username_to_claim, user_address);

        let state = borrow_global<State>(resource_address);
        let patchState = borrow_global<PatchState>(resource_address);

        let claim_events_count = event::counter(&state.claim_username_event);

        assert!(claim_events_count == 2, 7);

        assert!(smart_table::contains(&patchState.claimed_usernames, second_username_to_claim), 8);

        assert!(smart_table::contains(&patchState.friend_map, user_address), 9);

        let friends = smart_table::borrow(&patchState.friend_map, user_address);

        assert!(friends.count == 1, 10);

    }

    // test patch mint profile nft success
    #[test(admin = @kade, user = @0xCED, aptos_framework = @aptos_framework)]
    fun test_patch_mint_profile_nft_success(admin: &signer, user: &signer, aptos_framework: &signer) acquires PatchState, State, Profile {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let aptos_framework_address = signer::address_of(aptos_framework);
        let resource_address = account::create_resource_address(&@kade, SEED);

        let aptos =account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);
        patch_init_module(admin);

        let username_to_claim = string::utf8(b"kade");

        patch_claim_username(user, username_to_claim);

        patch_mint_profile_nft(user, username_to_claim, 1);

        let state = borrow_global<State>(resource_address);
        let patchState = borrow_global<PatchState>(resource_address);

        let mint_events_count = event::counter(&state.profile_mint_event);

        assert!(mint_events_count == 1, 7);

        assert!(smart_table::contains(&patchState.minted_nfts, user_address), 8);

        let nft_address = *smart_table::borrow(&patchState.minted_nfts, user_address);

        assert!(exists<Profile>(nft_address), 9);

        let profile = borrow_global<Profile>(nft_address);
        let expected_profile_name = string_utils::format2(&b"Profile #{} : {}",string_utils::to_string(&0), username_to_claim);
        debug::print<String>(&expected_profile_name);
        debug::print<Profile>(profile);

        assert!(profile.name == expected_profile_name, 10);
    }

    // test old mint and patch mint can work together
    #[test(admin = @kade, user = @0xCED, user2 = @0x54, aptos_framework = @aptos_framework)]
    fun test_old_mint_and_patch_mint_can_work_together(admin: &signer, user: &signer, user2: &signer, aptos_framework: &signer) acquires PatchState, State, Profile {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let user2_address = signer::address_of(user2);
        let aptos_framework_address = signer::address_of(aptos_framework);
        let resource_address = account::create_resource_address(&@kade, SEED);

        let aptos = account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);
        account::create_account_for_test(user2_address);

        init_module(admin);
        patch_init_module(admin);

        let username_to_claim = string::utf8(b"kade");
        let second_username_to_claim = string::utf8(b"not kade");
        claim_username(user, username_to_claim);
        patch_claim_username(user2, second_username_to_claim);

        mint_profile_nft(user, 1);
        patch_mint_profile_nft(user2, second_username_to_claim, 1);

        let state = borrow_global<State>(resource_address);
        let patchState = borrow_global<PatchState>(resource_address);

        let mint_events_count = event::counter(&state.profile_mint_event);

        assert!(mint_events_count == 2, 7);

        assert!(simple_map::contains_key(&state.minted_nfts, &user_address), 8);
        assert!(smart_table::contains(&patchState.minted_nfts, user2_address), 9);

        let nft_address = *simple_map::borrow(&state.minted_nfts, &user_address);
        let nft_address2 = *smart_table::borrow(&patchState.minted_nfts, user2_address);

        assert!(exists<Profile>(nft_address), 10);
        assert!(exists<Profile>(nft_address2), 11);

        let profile = borrow_global<Profile>(nft_address);
        let profile2 = borrow_global<Profile>(nft_address2);

        let expected_profile_name = string_utils::format2(
            &b"Profile #{} : {}",
            string_utils::to_string(&0),
            username_to_claim
        );
        let expected_profile_name2 = string_utils::format2(
            &b"Profile #{} : {}",
            string_utils::to_string(&1),
            second_username_to_claim
        );

        assert!(profile.name == expected_profile_name, 12);
        assert!(profile2.name == expected_profile_name2, 13);


        debug::print<String>(&expected_profile_name);
        debug::print<Profile>(profile);
        debug::print<String>(&expected_profile_name2);
        debug::print<Profile>(profile2);
    }

    // assert claim 4 users, 2 with old and 2 with patch, the second user for each case will be reffered by the first
    #[test(admin = @kade, user = @0xCED, user2 = @0x54, user3 = @0x55, user4 = @0x56, aptos_framework = @aptos_framework)]
    fun test_claim_4_users_2_old_2_patch(admin: &signer, user: &signer, user2: &signer, user3: &signer, user4: &signer, aptos_framework: &signer) acquires PatchState, State {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let user2_address = signer::address_of(user2);
        let user3_address = signer::address_of(user3);
        let user4_address = signer::address_of(user4);
        let aptos_framework_address = signer::address_of(aptos_framework);
        let resource_address = account::create_resource_address(&@kade, SEED);

        let aptos = account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);
        account::create_account_for_test(user2_address);
        account::create_account_for_test(user3_address);
        account::create_account_for_test(user4_address);

        init_module(admin);
        patch_init_module(admin);

        let username_to_claim = string::utf8(b"kade");
        let second_username_to_claim = string::utf8(b"not kade");
        let third_username_to_claim = string::utf8(b"not kade 2");
        let fourth_username_to_claim = string::utf8(b"not kade 3");

        claim_username(user, username_to_claim);
        patch_claim_username(user3, third_username_to_claim);

        claim_username_reffered(user2, second_username_to_claim, user_address);
        patch_claim_username_reffered(user4, fourth_username_to_claim, user3_address);

        mint_profile_nft(user, 1);
        patch_mint_profile_nft(user3, third_username_to_claim, 1);
        mint_profile_nft(user2, 1);
        patch_mint_profile_nft(user4, fourth_username_to_claim, 1);

        let state = borrow_global<State>(resource_address);
        let patchState = borrow_global<PatchState>(resource_address);

        let mint_events_count = event::counter(&state.profile_mint_event);

        assert!(mint_events_count == 4, 7);

        assert!(simple_map::contains_key(&state.minted_nfts, &user_address), 8);

        assert!(smart_table::contains(&patchState.minted_nfts, user3_address), 9);

        assert!(simple_map::contains_key(&state.minted_nfts, &user2_address), 10);

        assert!(smart_table::contains(&patchState.minted_nfts, user3_address), 11);

        let nft_address = *simple_map::borrow(&state.minted_nfts, &user_address);

        let nft_address2 = *smart_table::borrow(&patchState.minted_nfts, user3_address);

        let nft_address3 = *simple_map::borrow(&state.minted_nfts, &user2_address);

        let nft_address4 = *smart_table::borrow(&patchState.minted_nfts, user4_address);

        assert!(exists<Profile>(nft_address), 12);

        assert!(exists<Profile>(nft_address2), 13);

        assert!(exists<Profile>(nft_address3), 14);

        assert!(exists<Profile>(nft_address4), 15);


    }


    // Test patch view functions
    #[test(admin = @kade, user = @0xCED, aptos_framework = @aptos_framework)]
    fun test_patch_get_profile_nft_success(admin: &signer, user: &signer, aptos_framework: &signer) acquires State, Profile, PatchState {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let aptos_framework_address = signer::address_of(aptos_framework);

        let aptos =account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);
        patch_init_module(admin);

        let username_to_claim = string::utf8(b"kade");

        claim_username(user, username_to_claim);

        mint_profile_nft(user, 1);

        let (profile_name, variant, uri) = get_profile_nft(user_address);
        let (patch_profile_name, patch_variant, patch_uri) = patch_get_profile_nft(user_address);

        let expected_profile_name = string_utils::format2(&b"Profile #{} : {}",string_utils::to_string(&0), username_to_claim);

        assert!(profile_name == patch_profile_name, 7);
        assert!(expected_profile_name == patch_profile_name, 7);
        assert!(variant == patch_variant, 8);
        assert!(uri == patch_uri, 9);

    }

    // Test patch view functions
    #[test(admin = @kade, user = @0xCED, aptos_framework = @aptos_framework)]
    fun test_patch_user_exists_success(admin: &signer, user: &signer, aptos_framework: &signer) acquires State, PatchState {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let aptos_framework_address = signer::address_of(aptos_framework);

        let aptos = account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);
        patch_init_module(admin);

        let username_to_claim = string::utf8(b"kade");

        claim_username(user, username_to_claim);

        let exists = user_exists(user_address);
        let patch_exists = patch_user_exists(user_address);

        assert!(exists == patch_exists, 7);
    }

    // Test get claimed username
    #[test(admin = @kade, user = @0xCED, aptos_framework = @aptos_framework)]
    fun test_get_claimed_username_success(admin: &signer, user: &signer, aptos_framework: &signer) acquires State, PatchState {
        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        let aptos_framework_address = signer::address_of(aptos_framework);

        let aptos = account::create_account_for_test(aptos_framework_address);
        timestamp::set_time_has_started_for_testing(&aptos);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);
        patch_init_module(admin);

        let username_to_claim = string::utf8(b"kade");

        claim_username(user, username_to_claim);

        let claimed_username = get_claimed_username(user_address);
        let patch_claimed_username = patch_get_claimed_username(user_address);

        debug::print(&claimed_username);

        assert!(claimed_username == patch_claimed_username, 7);
    }




}