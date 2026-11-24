import type { Page } from '@playwright/test';

export async function selectOption(page:Page,id:string,value:string) {
  await page.locator('#'+id).click();
  await page.getByRole('listbox').locator(`[data-option="${value}"]`).click();
}

export async function countOptions(page:Page,id:string) {
  await page.locator('#'+id).click();
  const options=page.getByRole('option');
  await options.first().waitFor();
  const count=await options.count();
  await page.keyboard.press('Escape');
  return count;
}
