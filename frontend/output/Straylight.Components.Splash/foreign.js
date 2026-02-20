export const dismissImpl = () => {
  const splash = document.getElementById('splash');
  if (splash) {
    splash.classList.add('splash-out');
    setTimeout(() => {
      splash.style.display = 'none';
    }, 450);
  }
};
