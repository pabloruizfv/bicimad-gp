-- Allow the complete local avatar catalogue to be used by social profiles.
alter table public.profiles
  drop constraint if exists profiles_avatar_key;

alter table public.profiles
  add constraint profiles_avatar_key check (
    avatar_key in (
      '1.png', '2.png', '3.png', '4.png',
      '5.png', '6.png', '7.png', '8.png',
      '9.png', '10.png', '11.png', '12.png'
    )
  );
