// Document Head FFI for Hydrogen

export const setTitleImpl = (title) => () => {
  document.title = title;
};

export const getTitleImpl = () => {
  return document.title;
};

export const setMetaImpl = (name) => (content) => () => {
  // Check if it's an og: or twitter: tag (uses property instead of name)
  const isProperty = name.startsWith('og:') || name.startsWith('twitter:');
  const attr = isProperty ? 'property' : 'name';
  
  let meta = document.querySelector(`meta[${attr}="${name}"]`);
  
  if (!meta) {
    meta = document.createElement('meta');
    meta.setAttribute(attr, name);
    document.head.appendChild(meta);
  }
  
  meta.setAttribute('content', content);
};

export const removeMetaImpl = (name) => () => {
  const isProperty = name.startsWith('og:') || name.startsWith('twitter:');
  const attr = isProperty ? 'property' : 'name';
  const meta = document.querySelector(`meta[${attr}="${name}"]`);
  
  if (meta) {
    meta.remove();
  }
};

export const getMetaImpl = (name) => () => {
  const isProperty = name.startsWith('og:') || name.startsWith('twitter:');
  const attr = isProperty ? 'property' : 'name';
  const meta = document.querySelector(`meta[${attr}="${name}"]`);
  
  return meta ? meta.getAttribute('content') : null;
};

export const addLinkImpl = (rel) => (href) => (as) => () => {
  // Check for existing
  let link = document.querySelector(`link[rel="${rel}"][href="${href}"]`);
  
  if (!link) {
    link = document.createElement('link');
    link.rel = rel;
    link.href = href;
    if (as) {
      link.as = as;
    }
    document.head.appendChild(link);
  }
};

export const removeLinkImpl = (rel) => () => {
  const links = document.querySelectorAll(`link[rel="${rel}"]`);
  links.forEach(link => { link.remove(); });
};

export const setFaviconImpl = (href) => () => {
  let link = document.querySelector('link[rel="icon"]');
  
  if (!link) {
    link = document.createElement('link');
    link.rel = 'icon';
    document.head.appendChild(link);
  }
  
  link.href = href;
};
