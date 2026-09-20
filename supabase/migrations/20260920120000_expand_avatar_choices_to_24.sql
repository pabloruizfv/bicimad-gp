-- Keep the database catalogue aligned with the local assets bundled in the app.
alter table public.profiles
  drop constraint if exists profiles_avatar_key;

alter table public.profiles
  add constraint profiles_avatar_key check (
    avatar_key in (
      '1.png', '2.png', '3.png', '4.png',
      '5.png', '6.png', '7.png', '8.png',
      '9.png', '10.png', '11.png', '12.png',
      '13.png', '14.png', '15.png', '16.png',
      '17.png', '18.png', '19.png', '20.png',
      '21.png', '22.png', '23.png', '24.png'
    )
  );
