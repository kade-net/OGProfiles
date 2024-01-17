/**
 This smart contract enables new users to kade to claim usernames
 and old users to onboard their profiles onto the new network
 It also enables these users to create nfts of their profiles
**/


module kade::OGProfilesNftTest4 {

    use std::option;
    use std::signer;
    use std::string;
    use std::string::String;
    use std::vector;
    use aptos_std::simple_map;
    use aptos_std::simple_map::SimpleMap;
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
    const COLLECTION_NAME: vector<u8> = b"OG Profiles Collection";
    const COLLECTION_DESCRIPTION: vector<u8> = b"Collection of Kade/Network's OG Profiles";
    const COLLECTION_URI: vector<u8> = b"collection URI";

    const EXPLORER_1_URI: vector<u8> = b"https://orange-urban-sloth-806.mypinata.cloud/ipfs/QmWcy4azPJ5KZEtpGeMBu3eCn3XxVeukD6Nos9EcZqyWRb?_gl=1*1m4yyd2*_ga*OTAyMjc0MDk2LjE3MDM1Nzk3MDE.*_ga_5RMPXG14TE*MTcwNTI5NDI1MS41LjEuMTcwNTI5NDI4MS4zMC4wLjA.";
    const EXPLORER_2_URI: vector<u8> = b"https://orange-urban-sloth-806.mypinata.cloud/ipfs/QmUYL6gALaNAFj3RpnfXvSHphJnagmFFEwTFCy8cRw9pgd?_gl=1*f334fl*_ga*OTAyMjc0MDk2LjE3MDM1Nzk3MDE.*_ga_5RMPXG14TE*MTcwNTI5NDI1MS41LjEuMTcwNTI5NDI4MS4zMC4wLjA.";
    const PIOONER_1_URI: vector<u8> = b"https://orange-urban-sloth-806.mypinata.cloud/ipfs/Qmc7x9HedC2qbwqpYyVELw7ceMdnPqbvdjH5neqchZwnYV?_gl=1*f334fl*_ga*OTAyMjc0MDk2LjE3MDM1Nzk3MDE.*_ga_5RMPXG14TE*MTcwNTI5NDI1MS41LjEuMTcwNTI5NDI4MS4zMC4wLjA.";
    const PIOONER_2_URI: vector<u8> = b"https://orange-urban-sloth-806.mypinata.cloud/ipfs/Qmaw8phxUiCeEUkhDBTztxDtV9TXwzYEdNiRY7oiBjodVV?_gl=1*mv0e7f*_ga*OTAyMjc0MDk2LjE3MDM1Nzk3MDE.*_ga_5RMPXG14TE*MTcwNTI5NDI1MS41LjEuMTcwNTI5NDI4MS4zMC4wLjA.";

    // seed for the module's resource account
    const SEED: vector<u8> = b"og profiles ::test-4";

    // Error codes
    const EUserNameExists: u64 = 1;
    const EAddressDoesNotExist: u64 = 2;
    const EProfileDoesNotExist: u64 = 3;
    const EVariantDoesNotExist: u64 = 4;


    struct Profile has key {
        name: String,
        variant: u64,
        uri: String,
    }

    struct State has key {
        claimed_usernames: SimpleMap<address,string::String>,
        minted_nfts: SimpleMap<address, address>,
        signer_capability: SignerCapability,
        claim_username_event: EventHandle<ClaimUsernameEvent>,
        collection_address: address,
        minted_profiles: u64,
        profile_mint_event: EventHandle<ProfileMintEvent>,
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
        };

        move_to(&resource_signer, state)
    }

    public entry fun claim_username(
        claimer: &signer,
        username: String,
    ) acquires State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        assert_username_unclaimed(username);

        let state = borrow_global_mut<State>(resource_address);


        simple_map::add(&mut state.claimed_usernames, signer::address_of(claimer), username);

        event::emit_event(&mut state.claim_username_event, ClaimUsernameEvent{
            username,
            owner: signer::address_of(claimer),
            timestamp_seconds: timestamp::now_seconds(),
        });
    }

    // user who has already claimed a username can claim a profile nft
    public entry fun mint_profile_nft(claimer: &signer, variant: u64) acquires State {
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

    inline fun assert_username_unclaimed(username: String) acquires State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global<State>(resource_address);

        let values = simple_map::values(&state.claimed_usernames);
        assert!(!vector::contains(&values, &username), EUserNameExists);
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

    // Check if a username has already been claimed
    #[view]
    public fun is_username_claimed(username: String): bool acquires  State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global<State>(resource_address);
        let values = simple_map::values(&state.claimed_usernames);
        vector::contains(&values, &username)
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

    // Check if a user already exists
    #[view]
    public fun user_exists(claimer_address: address): bool acquires  State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global<State>(resource_address);
        // check if address exists
        simple_map::contains_key(&state.claimed_usernames, &claimer_address)
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

}